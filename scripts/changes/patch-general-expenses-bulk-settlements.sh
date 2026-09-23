#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# Fixxir General Expenses + Bulk Settlements Patch
# ==========================================================
#
# Adds:
#   - General_Expenses
#   - Settlements
#   - Settlement_Allocations
#   - General expense UI inside Finance
#   - Technician/vendor bulk settlement UI
#   - One Finance_Ledger debit per settlement (not one per allocation)
#   - Allocation links back to Repairs and/or Purchases
#   - Repair profitability includes settlement allocations linked to that repair
#   - Purchase detail shows vendor-settlement allocations
#
# Accounting behavior:
#   * General expenses are real cash debits and create one Finance_Ledger row.
#   * Bulk settlements create one Finance_Ledger debit for the total paid.
#   * Settlement allocations are reference/cost allocations only; they DO NOT
#     create extra Finance_Ledger debits, so cash is not duplicated.
#   * A general expense linked to a Repair counts as that repair's direct cost.
#   * A general expense linked to a Purchase is reference-only and does NOT
#     alter landed cost. Acquisition costs should still be entered as Purchase
#     shared costs so landed cost remains correct.
#
# Run from the Fixxir repo root:
#   chmod +x patch-general-expenses-bulk-settlements.sh
#   ./patch-general-expenses-bulk-settlements.sh
#   git diff --check
#   git diff -- Code.js Index.html
#   npm run deploy
# ==========================================================

CODE_FILE="${1:-Code.js}"
INDEX_FILE="${2:-Index.html}"

for f in "$CODE_FILE" "$INDEX_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: $f not found."
    echo "Run this patch from the Fixxir repository root."
    exit 1
  fi
done

if grep -q 'FIXXIR_FINANCE_OPS_V1' "$CODE_FILE" && \
   grep -q 'FIXXIR_FINANCE_OPS_UI_V1' "$INDEX_FILE"; then
  echo "General Expenses / Bulk Settlements patch is already installed."
  exit 0
fi

cp "$CODE_FILE" "${CODE_FILE}.before-finance-ops-v1.bak"
cp "$INDEX_FILE" "${INDEX_FILE}.before-finance-ops-v1.bak"

python3 - "$CODE_FILE" "$INDEX_FILE" <<'PY'
from pathlib import Path
import re
import sys

code_path = Path(sys.argv[1])
html_path = Path(sys.argv[2])

code = code_path.read_text(encoding="utf-8")
html = html_path.read_text(encoding="utf-8")

def must_find(text, needle, label):
    if needle not in text:
        raise SystemExit(
            f"ERROR: Could not find anchor for {label}. "
            "Backups were created; source files were not written."
        )

# ==========================================================
# Code.js — sheet names + prefixes
# ==========================================================

if 'generalExpenses: "General_Expenses"' not in code:
    anchor = '    finance: "Finance_Ledger",\n'
    must_find(code, anchor, "Finance_Ledger sheet")
    code = code.replace(
        anchor,
        anchor
        + '    generalExpenses: "General_Expenses",\n'
        + '    settlements: "Settlements",\n'
        + '    settlementAllocations: "Settlement_Allocations",\n',
        1,
    )

if 'General_Expenses: "GEX"' not in code:
    anchor = '    Finance_Ledger: "TXN",\n'
    must_find(code, anchor, "Finance_Ledger prefix")
    code = code.replace(
        anchor,
        anchor
        + '    General_Expenses: "GEX",\n'
        + '    Settlements: "STL",\n'
        + '    Settlement_Allocations: "STA",\n',
        1,
    )

# ==========================================================
# Code.js — schema constants
# ==========================================================

if "const FIXXIR_GENERAL_EXPENSE_HEADERS" not in code:
    do_get = code.find("function doGet()")
    if do_get < 0:
        raise SystemExit("ERROR: Could not locate doGet().")

    constants = r'''
/* FIXXIR_FINANCE_OPS_V1 */

const FIXXIR_GENERAL_EXPENSE_HEADERS = Object.freeze([
  "General_Expense_ID",
  "Expense_Date",
  "Category",
  "Description",
  "Amount",
  "Payment_Method",
  "Account",
  "Payee",
  "Supplier_ID",
  "Reference_Type",
  "Reference_ID",
  "Repair_ID",
  "Purchase_ID",
  "Finance_Transaction_ID",
  "Created_At",
  "Created_By",
  "Notes",
]);

const FIXXIR_SETTLEMENT_HEADERS = Object.freeze([
  "Settlement_ID",
  "Settlement_Date",
  "Payee_Type",
  "Payee_ID",
  "Payee_Name",
  "Amount",
  "Allocated_Amount",
  "Unallocated_Amount",
  "Payment_Method",
  "Account",
  "Payment_Reference",
  "Finance_Transaction_ID",
  "Created_At",
  "Created_By",
  "Notes",
]);

const FIXXIR_SETTLEMENT_ALLOCATION_HEADERS = Object.freeze([
  "Settlement_Allocation_ID",
  "Settlement_ID",
  "Settlement_Date",
  "Payee_Type",
  "Payee_ID",
  "Reference_Type",
  "Reference_ID",
  "Amount",
  "Created_At",
  "Created_By",
  "Notes",
]);

'''
    code = code[:do_get] + constants + code[do_get:]

# ==========================================================
# Code.js — initialization
# ==========================================================

if "ensureFinanceOperationsSchema_(ss);" not in code:
    required_anchor = "  const requiredSheets = Object.values(FIXXIR.sheets);\n"
    must_find(code, required_anchor, "initialize requiredSheets")
    code = code.replace(
        required_anchor,
        "  ensureFinanceOperationsSchema_(ss);\n\n" + required_anchor,
        1,
    )

# ==========================================================
# Code.js — bootstrap already has technicians/suppliers in current build.
# Nothing additional needed.
# ==========================================================

# ==========================================================
# Code.js — Finance operations backend
# ==========================================================

if "function createGeneralExpense(payload)" not in code:
    anchor = "/* ---------------- Data helpers ---------------- */\n"
    must_find(code, anchor, "Data helpers section")

    backend = r'''
/* ---------------- General Expenses / Bulk Settlements ---------------- */

function getFinanceOperationsData(filters) {
  assertAuthorized_();
  ensureFinanceOperationsSchema_(getSpreadsheet_());

  filters = filters || {};

  return {
    generalExpenses: listGeneralExpenses_(filters),
    settlements: listSettlements_(filters),
    summary: getFinanceOperationsSummary_(),
  };
}

function createGeneralExpense(payload) {
  assertAuthorized_();
  ensureFinanceOperationsSchema_(getSpreadsheet_());

  payload = payload || {};
  requireFields_(payload, [
    "Expense_Date",
    "Category",
    "Description",
    "Amount",
    "Payment_Method",
  ]);

  const expenseDate = parseDate_(payload.Expense_Date);
  if (!expenseDate) throw new Error("Expense date is required.");

  const amount = number_(payload.Amount);
  if (!(amount > 0)) throw new Error("Expense amount must be greater than zero.");

  const referenceType = clean_(payload.Reference_Type);
  const referenceId = clean_(payload.Reference_ID);

  if (referenceType && !["Repair", "Purchase"].includes(referenceType)) {
    throw new Error("Expense link must be Repair, Purchase, or blank.");
  }

  let repairId = "";
  let purchaseId = "";

  if (referenceType === "Repair") {
    repairId = referenceId;
    if (!repairId) throw new Error("Enter the Repair ID to link this expense.");
    if (!findById_(FIXXIR.sheets.repairs, "Repair_ID", repairId)) {
      throw new Error("Repair not found: " + repairId);
    }
  }

  if (referenceType === "Purchase") {
    purchaseId = referenceId;
    if (!purchaseId) throw new Error("Enter the Purchase ID to link this expense.");
    if (!findById_(FIXXIR.sheets.purchases, "Purchase_ID", purchaseId)) {
      throw new Error("Purchase not found: " + purchaseId);
    }
  }

  const supplierId = clean_(payload.Supplier_ID);
  if (
    supplierId &&
    !findById_(FIXXIR.sheets.suppliers, "Supplier_ID", supplierId)
  ) {
    throw new Error("Vendor not found: " + supplierId);
  }

  const expenseId = generateId_(FIXXIR.sheets.generalExpenses);
  const now = new Date();

  const txnId = appendFinanceDebit_({
    Date: expenseDate,
    Category: clean_(payload.Category),
    Amount: amount,
    Payment_Method: clean_(payload.Payment_Method),
    Account: clean_(payload.Account) || "Operating",
    Repair_ID: repairId,
    Purchase_ID: purchaseId,
    General_Expense_ID: expenseId,
    Supplier_ID: supplierId,
    Reference_Type: referenceType || "General Expense",
    Reference_ID: referenceId || expenseId,
    Description: clean_(payload.Description),
    Receipt_Reference: clean_(payload.Receipt_Reference),
    Notes: clean_(payload.Notes),
  });

  appendRecord_(FIXXIR.sheets.generalExpenses, {
    General_Expense_ID: expenseId,
    Expense_Date: expenseDate,
    Category: clean_(payload.Category),
    Description: clean_(payload.Description),
    Amount: amount,
    Payment_Method: clean_(payload.Payment_Method),
    Account: clean_(payload.Account) || "Operating",
    Payee: clean_(payload.Payee),
    Supplier_ID: supplierId,
    Reference_Type: referenceType,
    Reference_ID: referenceId,
    Repair_ID: repairId,
    Purchase_ID: purchaseId,
    Finance_Transaction_ID: txnId,
    Created_At: now,
    Created_By: currentUser_(),
    Notes: clean_(payload.Notes),
  });

  return findById_(
    FIXXIR.sheets.generalExpenses,
    "General_Expense_ID",
    expenseId,
  );
}

function createBulkSettlement(payload) {
  assertAuthorized_();
  ensureFinanceOperationsSchema_(getSpreadsheet_());

  payload = payload || {};
  requireFields_(payload, [
    "Settlement_Date",
    "Payee_Type",
    "Payee_ID",
    "Amount",
    "Payment_Method",
  ]);

  const payeeType = clean_(payload.Payee_Type);
  if (!["Technician", "Vendor"].includes(payeeType)) {
    throw new Error("Payee type must be Technician or Vendor.");
  }

  const payeeId = clean_(payload.Payee_ID);
  const payee = getSettlementPayee_(payeeType, payeeId);
  if (!payee) {
    throw new Error(payeeType + " not found: " + payeeId);
  }

  const settlementDate = parseDate_(payload.Settlement_Date);
  if (!settlementDate) throw new Error("Settlement date is required.");

  const amount = number_(payload.Amount);
  if (!(amount > 0)) {
    throw new Error("Settlement amount must be greater than zero.");
  }

  let allocations = payload.Allocations || [];
  if (typeof allocations === "string") {
    try {
      allocations = JSON.parse(allocations || "[]");
    } catch (error) {
      throw new Error("Settlement allocations could not be read.");
    }
  }
  if (!Array.isArray(allocations)) allocations = [];

  const cleanAllocations = allocations
    .map((allocation, index) => {
      const referenceType = clean_(allocation.Reference_Type);
      const referenceId = clean_(allocation.Reference_ID);
      const allocationAmount = number_(allocation.Amount);

      if (!referenceType && !referenceId && !(allocationAmount > 0)) {
        return null;
      }

      if (!["Repair", "Purchase"].includes(referenceType)) {
        throw new Error(
          `Allocation ${index + 1}: choose Repair or Purchase.`,
        );
      }

      if (!referenceId) {
        throw new Error(
          `Allocation ${index + 1}: enter the Repair/Purchase ID.`,
        );
      }

      if (!(allocationAmount > 0)) {
        throw new Error(
          `Allocation ${index + 1}: amount must be greater than zero.`,
        );
      }

      validateSettlementAllocation_(
        payeeType,
        payeeId,
        referenceType,
        referenceId,
      );

      return {
        Reference_Type: referenceType,
        Reference_ID: referenceId,
        Amount: allocationAmount,
        Notes: clean_(allocation.Notes),
      };
    })
    .filter(Boolean);

  const allocatedAmount = cleanAllocations.reduce(
    (sum, allocation) => sum + allocation.Amount,
    0,
  );

  if (allocatedAmount > amount + 0.0001) {
    throw new Error(
      "Allocated amount cannot exceed the total settlement amount.",
    );
  }

  const settlementId = generateId_(FIXXIR.sheets.settlements);
  const now = new Date();
  const payeeName = getSettlementPayeeName_(payeeType, payee);

  const txnId = appendFinanceDebit_({
    Date: settlementDate,
    Category:
      payeeType === "Technician"
        ? "Technician Settlement"
        : "Vendor Settlement",
    Amount: amount,
    Payment_Method: clean_(payload.Payment_Method),
    Account: clean_(payload.Account) || "Operating",
    Settlement_ID: settlementId,
    Supplier_ID: payeeType === "Vendor" ? payeeId : "",
    Technician_ID: payeeType === "Technician" ? payeeId : "",
    Reference_Type: "Settlement",
    Reference_ID: settlementId,
    Description:
      clean_(payload.Description) ||
      `${payeeType} settlement · ${payeeName}`,
    Receipt_Reference: clean_(payload.Payment_Reference),
    Notes: clean_(payload.Notes),
  });

  appendRecord_(FIXXIR.sheets.settlements, {
    Settlement_ID: settlementId,
    Settlement_Date: settlementDate,
    Payee_Type: payeeType,
    Payee_ID: payeeId,
    Payee_Name: payeeName,
    Amount: amount,
    Allocated_Amount: allocatedAmount,
    Unallocated_Amount: Math.max(0, amount - allocatedAmount),
    Payment_Method: clean_(payload.Payment_Method),
    Account: clean_(payload.Account) || "Operating",
    Payment_Reference: clean_(payload.Payment_Reference),
    Finance_Transaction_ID: txnId,
    Created_At: now,
    Created_By: currentUser_(),
    Notes: clean_(payload.Notes),
  });

  cleanAllocations.forEach((allocation) => {
    appendRecord_(FIXXIR.sheets.settlementAllocations, {
      Settlement_Allocation_ID: generateId_(
        FIXXIR.sheets.settlementAllocations,
      ),
      Settlement_ID: settlementId,
      Settlement_Date: settlementDate,
      Payee_Type: payeeType,
      Payee_ID: payeeId,
      Reference_Type: allocation.Reference_Type,
      Reference_ID: allocation.Reference_ID,
      Amount: allocation.Amount,
      Created_At: now,
      Created_By: currentUser_(),
      Notes: allocation.Notes,
    });
  });

  return getSettlement_(settlementId);
}

function getSettlement_(settlementId) {
  const settlement = findById_(
    FIXXIR.sheets.settlements,
    "Settlement_ID",
    settlementId,
  );

  if (!settlement) return null;

  return {
    settlement,
    allocations: getRecords_(FIXXIR.sheets.settlementAllocations)
      .filter((row) => row.Settlement_ID === settlementId),
  };
}

function listGeneralExpenses_(filters) {
  filters = filters || {};
  const q = clean_(filters.expenseQ || filters.q).toLowerCase();

  let rows = getRecords_(FIXXIR.sheets.generalExpenses);

  if (q) {
    rows = rows.filter((row) =>
      [
        row.General_Expense_ID,
        row.Category,
        row.Description,
        row.Payee,
        row.Reference_ID,
        row.Supplier_ID,
      ].some((value) =>
        String(value || "").toLowerCase().includes(q),
      ),
    );
  }

  rows.sort((a, b) => {
    const dateCmp = String(b.Expense_Date || "").localeCompare(
      String(a.Expense_Date || ""),
    );
    if (dateCmp) return dateCmp;
    return String(b.Created_At || "").localeCompare(
      String(a.Created_At || ""),
    );
  });

  return rows.slice(0, 250);
}

function listSettlements_(filters) {
  filters = filters || {};
  const q = clean_(filters.settlementQ || filters.q).toLowerCase();

  const allocations = getRecords_(FIXXIR.sheets.settlementAllocations);
  const allocationMap = {};

  allocations.forEach((allocation) => {
    const id = allocation.Settlement_ID;
    if (!id) return;
    if (!allocationMap[id]) allocationMap[id] = [];
    allocationMap[id].push(allocation);
  });

  let rows = getRecords_(FIXXIR.sheets.settlements).map((settlement) =>
    Object.assign({}, settlement, {
      Allocations: allocationMap[settlement.Settlement_ID] || [],
      Allocation_Count:
        (allocationMap[settlement.Settlement_ID] || []).length,
    }),
  );

  if (q) {
    rows = rows.filter((row) =>
      [
        row.Settlement_ID,
        row.Payee_Type,
        row.Payee_ID,
        row.Payee_Name,
        row.Payment_Reference,
        row.Notes,
        ...(row.Allocations || []).map(
          (allocation) =>
            `${allocation.Reference_Type} ${allocation.Reference_ID}`,
        ),
      ].some((value) =>
        String(value || "").toLowerCase().includes(q),
      ),
    );
  }

  rows.sort((a, b) => {
    const dateCmp = String(b.Settlement_Date || "").localeCompare(
      String(a.Settlement_Date || ""),
    );
    if (dateCmp) return dateCmp;
    return String(b.Created_At || "").localeCompare(
      String(a.Created_At || ""),
    );
  });

  return rows.slice(0, 250);
}

function getFinanceOperationsSummary_() {
  const expenses = getRecords_(FIXXIR.sheets.generalExpenses);
  const settlements = getRecords_(FIXXIR.sheets.settlements);

  return {
    generalExpenseTotal: expenses.reduce(
      (sum, row) => sum + number_(row.Amount),
      0,
    ),
    settlementTotal: settlements.reduce(
      (sum, row) => sum + number_(row.Amount),
      0,
    ),
    unallocatedSettlements: settlements.reduce(
      (sum, row) => sum + number_(row.Unallocated_Amount),
      0,
    ),
    settlementCount: settlements.length,
  };
}

function validateSettlementAllocation_(
  payeeType,
  payeeId,
  referenceType,
  referenceId
) {
  if (referenceType === "Repair") {
    const repair = findById_(
      FIXXIR.sheets.repairs,
      "Repair_ID",
      referenceId,
    );
    if (!repair) throw new Error("Repair not found: " + referenceId);

    if (
      payeeType === "Technician" &&
      repair.Technician_ID &&
      repair.Technician_ID !== payeeId
    ) {
      throw new Error(
        `${referenceId} is assigned to another technician.`,
      );
    }

    return true;
  }

  if (referenceType === "Purchase") {
    const purchase = findById_(
      FIXXIR.sheets.purchases,
      "Purchase_ID",
      referenceId,
    );
    if (!purchase) throw new Error("Purchase not found: " + referenceId);

    if (
      payeeType === "Vendor" &&
      purchase.Supplier_ID &&
      purchase.Supplier_ID !== payeeId
    ) {
      throw new Error(
        `${referenceId} belongs to a different vendor.`,
      );
    }

    return true;
  }

  throw new Error("Settlement allocation must reference a Repair or Purchase.");
}

function getSettlementPayee_(payeeType, payeeId) {
  if (payeeType === "Technician") {
    return findById_(
      FIXXIR.sheets.technicians,
      "Technician_ID",
      payeeId,
    );
  }

  if (payeeType === "Vendor") {
    return findById_(
      FIXXIR.sheets.suppliers,
      "Supplier_ID",
      payeeId,
    );
  }

  return null;
}

function getSettlementPayeeName_(payeeType, payee) {
  payee = payee || {};

  if (payeeType === "Technician") {
    return clean_(
      payee.Full_Name ||
      payee.Name ||
      payee.Technician_ID
    );
  }

  return clean_(
    payee.Supplier_Name ||
    payee.Company_Name ||
    payee.Name ||
    payee.Full_Name ||
    payee.Contact_Name ||
    payee.Supplier_ID
  );
}

function appendFinanceDebit_(payload) {
  ensureFinanceOperationsSchema_(getSpreadsheet_());

  const txnId = generateId_(FIXXIR.sheets.finance);

  appendRecord_(FIXXIR.sheets.finance, {
    Transaction_ID: txnId,
    Date: parseDate_(payload.Date) || new Date(),
    Transaction_Type: "Debit",
    Category: clean_(payload.Category),
    Amount: number_(payload.Amount),
    Payment_Method: clean_(payload.Payment_Method),
    Account: clean_(payload.Account) || "Operating",
    Repair_ID: clean_(payload.Repair_ID),
    Sales_ID: clean_(payload.Sales_ID),
    Purchase_ID: clean_(payload.Purchase_ID),
    Settlement_ID: clean_(payload.Settlement_ID),
    General_Expense_ID: clean_(payload.General_Expense_ID),
    Reference_Type: clean_(payload.Reference_Type) || "General",
    Reference_ID: clean_(payload.Reference_ID),
    Customer_ID: clean_(payload.Customer_ID),
    Supplier_ID: clean_(payload.Supplier_ID),
    Technician_ID: clean_(payload.Technician_ID),
    Description: clean_(payload.Description),
    Receipt_Reference: clean_(payload.Receipt_Reference),
    Entered_By: currentUser_(),
    Approval_Status: clean_(payload.Approval_Status) || "Approved",
    Notes: clean_(payload.Notes),
  });

  return txnId;
}

function getSettlementAllocationsFor_(
  referenceType,
  referenceId
) {
  ensureFinanceOperationsSchema_(getSpreadsheet_());

  return getRecords_(FIXXIR.sheets.settlementAllocations)
    .filter(
      (row) =>
        row.Reference_Type === referenceType &&
        row.Reference_ID === referenceId,
    )
    .sort((a, b) =>
      String(b.Settlement_Date || "").localeCompare(
        String(a.Settlement_Date || ""),
      ),
    );
}

function addSettlementRepairCostsToFinanceMap_(map) {
  ensureFinanceOperationsSchema_(getSpreadsheet_());

  getRecords_(FIXXIR.sheets.settlementAllocations)
    .filter((row) => row.Reference_Type === "Repair")
    .forEach((row) => {
      const id = row.Reference_ID;
      if (!id) return;
      if (!map[id]) map[id] = { credits: 0, debits: 0 };
      map[id].debits += number_(row.Amount);
    });

  return map;
}

function ensureFinanceOperationsSchema_(ss) {
  ss = ss || getSpreadsheet_();

  ensureSheetColumns_(
    ss,
    FIXXIR.sheets.generalExpenses,
    FIXXIR_GENERAL_EXPENSE_HEADERS,
  );

  ensureSheetColumns_(
    ss,
    FIXXIR.sheets.settlements,
    FIXXIR_SETTLEMENT_HEADERS,
  );

  ensureSheetColumns_(
    ss,
    FIXXIR.sheets.settlementAllocations,
    FIXXIR_SETTLEMENT_ALLOCATION_HEADERS,
  );

  // Existing Finance_Ledger rows remain untouched. These columns are appended
  // only if missing so new transactions can link to the new modules.
  ensureSheetColumns_(
    ss,
    FIXXIR.sheets.finance,
    [
      "Purchase_ID",
      "Settlement_ID",
      "General_Expense_ID",
      "Supplier_ID",
      "Technician_ID",
    ],
  );
}

'''
    code = code.replace(anchor, backend + anchor, 1)

# ==========================================================
# Code.js — repair profitability includes settlement allocations
# ==========================================================

# listRepairs already uses buildRepairFinanceMap_; mutate it immediately.
if "addSettlementRepairCostsToFinanceMap_(financeSummary);" not in code:
    anchor = "  const financeSummary = buildRepairFinanceMap_();\n"
    must_find(code, anchor, "listRepairs finance summary")
    code = code.replace(
        anchor,
        anchor + "  addSettlementRepairCostsToFinanceMap_(financeSummary);\n",
        1,
    )

# getRepair: calculate allocation-linked repair costs and expose links.
repair_start = code.find("function getRepair(repairId)")
repair_end = code.find("function searchCustomers", repair_start)
if repair_start < 0 or repair_end < 0:
    raise SystemExit("ERROR: Could not locate getRepair().")

region = code[repair_start:repair_end]

if "const settlementAllocations = getSettlementAllocationsFor_(" not in region:
    debit_anchor = '''  const debits = transactions
    .filter((t) => t.Transaction_Type === "Debit")
    .reduce((s, t) => s + number_(t.Amount), 0);
'''
    if debit_anchor not in region:
        raise SystemExit("ERROR: Could not find getRepair debit calculation.")
    region = region.replace(
        debit_anchor,
        debit_anchor
        + '''
  const settlementAllocations = getSettlementAllocationsFor_(
    "Repair",
    id,
  );
  const settlementCosts = settlementAllocations.reduce(
    (sum, row) => sum + number_(row.Amount),
    0,
  );
''',
        1,
    )

if "    settlementAllocations," not in region:
    # Put alongside transactions, tolerant of optional notes field.
    if "    transactions,\n" not in region:
        raise SystemExit("ERROR: Could not find getRepair return transactions.")
    region = region.replace(
        "    transactions,\n",
        "    transactions,\n    settlementAllocations,\n",
        1,
    )

region = region.replace(
    "      directCost: debits,\n      grossProfit: finalAmount - debits,\n",
    "      directCost: debits + settlementCosts,\n"
    "      settlementCosts,\n"
    "      grossProfit: finalAmount - debits - settlementCosts,\n",
    1,
)

code = code[:repair_start] + region + code[repair_end:]

# ==========================================================
# Code.js — purchase detail exposes vendor settlements
# ==========================================================

purchase_start = code.find("function getPurchase(purchaseId)")
purchase_end = code.find("function createPurchase(payload)", purchase_start)
if purchase_start < 0 or purchase_end < 0:
    raise SystemExit("ERROR: Could not locate getPurchase().")

region = code[purchase_start:purchase_end]

if 'getSettlementAllocationsFor_("Purchase", id)' not in region:
    # Insert before return.
    return_pos = region.find("  return {\n")
    if return_pos < 0:
        raise SystemExit("ERROR: Could not find getPurchase return block.")
    calc = '''  const settlementAllocations = getSettlementAllocationsFor_(
    "Purchase",
    id,
  );
  const supplierSettled = settlementAllocations
    .filter((row) => row.Payee_Type === "Vendor")
    .reduce((sum, row) => sum + number_(row.Amount), 0);
  const supplierDue = number_(purchase.Items_Subtotal);

'''
    region = region[:return_pos] + calc + region[return_pos:]

if "    settlementAllocations," not in region:
    # Put after expenses if present, otherwise after items.
    if "    expenses,\n" in region:
        region = region.replace(
            "    expenses,\n",
            "    expenses,\n"
            "    settlementAllocations,\n"
            "    settlementSummary: {\n"
            "      supplierDue,\n"
            "      supplierSettled,\n"
            "      supplierBalance: Math.max(0, supplierDue - supplierSettled),\n"
            "      supplierOverpaid: Math.max(0, supplierSettled - supplierDue),\n"
            "    },\n",
            1,
        )
    elif "    items,\n" in region:
        region = region.replace(
            "    items,\n",
            "    items,\n"
            "    settlementAllocations,\n"
            "    settlementSummary: {\n"
            "      supplierDue,\n"
            "      supplierSettled,\n"
            "      supplierBalance: Math.max(0, supplierDue - supplierSettled),\n"
            "      supplierOverpaid: Math.max(0, supplierSettled - supplierDue),\n"
            "    },\n",
            1,
        )
    else:
        raise SystemExit("ERROR: Could not add purchase settlement return fields.")

code = code[:purchase_start] + region + code[purchase_end:]

# ==========================================================
# Index.html — modals
# ==========================================================

if 'id="generalExpenseModal"' not in html:
    modal_match = re.search(
        r'''(?is)<div\b[^>]*\bid=["']financeModal["'][^>]*>''',
        html,
    )
    if not modal_match:
        modal_match = re.search(
            r'''(?is)<div\b[^>]*\bid=["']toast["'][^>]*>''',
            html,
        )
    if not modal_match:
        raise SystemExit("ERROR: Could not find modal insertion point.")

    modals = r'''<div class="modal" id="generalExpenseModal">
  <div class="modal-box" style="width:min(760px,100%)">
    <div class="modal-head">
      <h3>General Expense</h3>
      <button class="close" onclick="closeModal('generalExpenseModal')">×</button>
    </div>

    <form id="generalExpenseForm" onsubmit="submitGeneralExpense(event)">
      <div class="modal-body">
        <div class="form-grid">
          <div><label class="required">Expense date</label><input class="input" type="date" name="Expense_Date" id="generalExpenseDate" required></div>
          <div><label class="required">Category</label>
            <select class="select" name="Category" required>
              <option value="">Select category</option>
              <option>Utilities</option>
              <option>Tools & Equipment</option>
              <option>Rent</option>
              <option>Power / Fuel</option>
              <option>Internet / Data</option>
              <option>Transport / Logistics</option>
              <option>Office Supplies</option>
              <option>Marketing</option>
              <option>Bank Charges</option>
              <option>Maintenance</option>
              <option>Staff / Admin</option>
              <option>Other</option>
            </select>
          </div>

          <div class="full"><label class="required">Description</label><input class="input" name="Description" required placeholder="e.g. Workshop electricity, soldering station, office data"></div>
          <div><label class="required">Amount (₦)</label><input class="input" type="number" min="1" step="1" name="Amount" required></div>
          <div><label class="required">Payment method</label><select class="select" name="Payment_Method" id="generalExpensePaymentMethod" required></select></div>
          <div><label>Account</label><input class="input" name="Account" value="Operating"></div>
          <div><label>Payee</label><input class="input" name="Payee"></div>
          <div><label>Vendor (optional)</label><select class="select" name="Supplier_ID" id="generalExpenseSupplier"></select></div>

          <div><label>Link to</label>
            <select class="select" name="Reference_Type" id="generalExpenseReferenceType" onchange="updateGeneralExpenseReferencePlaceholder()">
              <option value="">Not linked</option>
              <option>Repair</option>
              <option>Purchase</option>
            </select>
          </div>
          <div><label>Repair / Purchase ID</label><input class="input" name="Reference_ID" id="generalExpenseReferenceId" placeholder="Optional"></div>

          <div><label>Receipt / bank reference</label><input class="input" name="Receipt_Reference"></div>
          <div class="full"><label>Notes</label><textarea class="textarea" name="Notes"></textarea></div>
        </div>

        <div class="muted" style="font-size:12px;margin-top:12px">
          If a cost belongs to acquiring stock, enter it under that Purchase's shared costs instead so landed cost remains correct.
        </div>
      </div>

      <div class="modal-foot">
        <button type="button" class="btn" onclick="closeModal('generalExpenseModal')">Cancel</button>
        <button class="btn primary" type="submit">Record expense</button>
      </div>
    </form>
  </div>
</div>

<div class="modal" id="bulkSettlementModal">
  <div class="modal-box" style="width:min(1000px,100%)">
    <div class="modal-head">
      <h3>Bulk Settlement</h3>
      <button class="close" onclick="closeModal('bulkSettlementModal')">×</button>
    </div>

    <form id="bulkSettlementForm" onsubmit="submitBulkSettlement(event)">
      <div class="modal-body">
        <div class="form-grid">
          <div><label class="required">Settlement date</label><input class="input" type="date" name="Settlement_Date" id="settlementDate" required></div>
          <div><label class="required">Payee type</label>
            <select class="select" name="Payee_Type" id="settlementPayeeType" onchange="fillSettlementPayees()" required>
              <option value="">Select</option>
              <option>Technician</option>
              <option>Vendor</option>
            </select>
          </div>

          <div><label class="required">Payee</label><select class="select" name="Payee_ID" id="settlementPayeeId" required></select></div>
          <div><label class="required">Total paid (₦)</label><input class="input" type="number" min="1" step="1" name="Amount" id="settlementAmount" oninput="recalcSettlementAllocation()" required></div>
          <div><label class="required">Payment method</label><select class="select" name="Payment_Method" id="settlementPaymentMethod" required></select></div>
          <div><label>Account</label><input class="input" name="Account" value="Operating"></div>
          <div><label>Payment reference</label><input class="input" name="Payment_Reference"></div>
          <div class="full"><label>Notes</label><textarea class="textarea" name="Notes"></textarea></div>
        </div>

        <div class="section-head" style="margin-top:24px">
          <div>
            <h3>Allocate settlement</h3>
            <div class="muted" style="font-size:12px;margin-top:4px">
              Link portions of this payment to repairs and/or purchases. You can leave part of the payment unallocated.
            </div>
          </div>
          <button type="button" class="btn small" onclick="addSettlementAllocationRow()">+ Add link</button>
        </div>

        <div id="settlementAllocations">
          <div class="empty" style="padding:14px">No links added yet.</div>
        </div>

        <div class="finance-box" style="margin-top:16px">
          <div class="finance-row"><span>Total paid</span><b id="settlementTotalView">₦0</b></div>
          <div class="finance-row"><span>Allocated</span><b id="settlementAllocatedView">₦0</b></div>
          <div class="finance-row big"><span>Unallocated</span><span id="settlementUnallocatedView">₦0</span></div>
        </div>
      </div>

      <div class="modal-foot">
        <button type="button" class="btn" onclick="closeModal('bulkSettlementModal')">Cancel</button>
        <button class="btn primary" type="submit">Record settlement</button>
      </div>
    </form>
  </div>
</div>

'''
    html = html[:modal_match.start()] + modals + html[modal_match.start():]

# ==========================================================
# Index.html — global
# ==========================================================

if "let SETTLEMENT_ALLOCATION_SEQ" not in html:
    script_match = re.search(r'''(?is)<script\b[^>]*>''', html)
    if not script_match:
        raise SystemExit("ERROR: Could not find <script>.")
    insert = '''
  let SETTLEMENT_ALLOCATION_SEQ = 0;
  let FINANCE_OPS_TIMER = null;
'''
    html = html[:script_match.end()] + insert + html[script_match.end():]

# ==========================================================
# Index.html — replace Finance page renderer
# ==========================================================

finance_match = re.search(
    r'''(?is)([ \t]*)function\s+renderFinancePage\s*\(\s*\)\s*\{.*?\n\1\}\s*\n(?=[ \t]*function\s+openNewRepair)''',
    html,
)

if not finance_match:
    # More permissive variant: stop before openNewRepair regardless of indentation.
    finance_match = re.search(
        r'''(?is)function\s+renderFinancePage\s*\(\s*\)\s*\{.*?\n[ \t]*\}\s*\n(?=[ \t]*function\s+openNewRepair)''',
        html,
    )

if not finance_match:
    raise SystemExit(
        "ERROR: Could not safely locate renderFinancePage() through openNewRepair()."
    )

finance_renderer = r'''function renderFinancePage() {
    document.getElementById('content').innerHTML=`
      <div class="toolbar">
        <div>
          <h2>Finance</h2>
          <div class="muted" style="margin-top:5px">Cash movement, general operating expenses, technician settlements and vendor settlements.</div>
        </div>
        <div class="actions">
          <button class="btn" onclick="openBulkSettlement()">+ Bulk Settlement</button>
          <button class="btn primary" onclick="openGeneralExpense()">+ General Expense</button>
        </div>
      </div>

      <div class="grid kpis" id="financeOpsKpis">
        ${kpi("Today's credits",money(BOOT.dashboard.todayCredits),'Cash/revenue posted today')}
        ${kpi("Today's debits",money(BOOT.dashboard.todayDebits),'Cash paid today')}
        ${kpi('General expenses','—','Recorded operating/general expenses')}
        ${kpi('Settlements','—','Technician and vendor bulk payments')}
      </div>

      <div class="card section" style="margin-bottom:18px">
        <div class="section-head"><h3>General expenses</h3><button class="btn small" onclick="openGeneralExpense()">+ Expense</button></div>
        <div class="filters" style="margin-bottom:14px">
          <input class="input" id="generalExpenseQ" placeholder="Search category, payee, description or linked ID…" oninput="debouncedFinanceOpsLoad()">
        </div>
        <div id="generalExpensesList"><div class="empty">Loading expenses…</div></div>
      </div>

      <div class="card section">
        <div class="section-head"><h3>Bulk settlements</h3><button class="btn small" onclick="openBulkSettlement()">+ Settlement</button></div>
        <div class="filters" style="margin-bottom:14px">
          <input class="input" id="settlementQ" placeholder="Search payee, settlement or linked repair/purchase…" oninput="debouncedFinanceOpsLoad()">
        </div>
        <div id="settlementsList"><div class="empty">Loading settlements…</div></div>
      </div>`;

    populateFinanceOpsSelects();
    loadFinanceOperations();
  }

'''

html = html[:finance_match.start()] + finance_renderer + html[finance_match.end():]

# ==========================================================
# Index.html — Finance operation JS helpers
# ==========================================================

if "function openGeneralExpense()" not in html:
    helper_anchor = re.search(
        r'''(?m)^[ \t]*function\s+openNewRepair\s*\(''',
        html,
    )
    if not helper_anchor:
        raise SystemExit("ERROR: Could not locate openNewRepair() for helper insertion.")

    helpers = r'''  /* FIXXIR_FINANCE_OPS_UI_V1 */

  function financeOpsToday(){
    const now=new Date();
    const local=new Date(now.getTime()-now.getTimezoneOffset()*60000);
    return local.toISOString().slice(0,10);
  }

  function populateFinanceOpsSelects(){
    fillSelect(
      'generalExpensePaymentMethod',
      BOOT.settings.Payment_Method||[],
      'Select method'
    );

    fillSelect(
      'settlementPaymentMethod',
      BOOT.settings.Payment_Method||[],
      'Select method'
    );

    fillSelect(
      'generalExpenseSupplier',
      (BOOT.suppliers||[]).map(s=>({
        value:s.Supplier_ID,
        label:s.Supplier_Name||s.Company_Name||s.Name||s.Supplier_ID
      })),
      'No vendor'
    );

    fillSettlementPayees();
  }

  function openGeneralExpense(){
    const form=document.getElementById('generalExpenseForm');
    form.reset();

    populateFinanceOpsSelects();
    document.getElementById('generalExpenseDate').value=financeOpsToday();
    updateGeneralExpenseReferencePlaceholder();
    document.getElementById('generalExpenseModal').classList.add('open');
  }

  function updateGeneralExpenseReferencePlaceholder(){
    const type=document.getElementById('generalExpenseReferenceType')?.value||'';
    const input=document.getElementById('generalExpenseReferenceId');
    if(!input)return;

    if(type==='Repair')input.placeholder='REP-000123';
    else if(type==='Purchase')input.placeholder='PUR-000123';
    else input.placeholder='Optional';

    if(!type)input.value='';
  }

  async function submitGeneralExpense(e){
    e.preventDefault();
    const data=formObject(e.target);

    showLoading(true);
    try{
      const row=await server('createGeneralExpense',data);
      closeModal('generalExpenseModal');
      toast(`Recorded ${row.General_Expense_ID}`);

      BOOT.dashboard=await server('refreshDashboard');
      if(CURRENT_PAGE==='finance')await loadFinanceOperations();
    }catch(err){
      toast(err.message,true);
    }finally{
      showLoading(false);
    }
  }

  function openBulkSettlement(){
    const form=document.getElementById('bulkSettlementForm');
    form.reset();

    SETTLEMENT_ALLOCATION_SEQ=0;
    document.getElementById('settlementAllocations').innerHTML=
      '<div class="empty" style="padding:14px">No links added yet.</div>';

    populateFinanceOpsSelects();
    document.getElementById('settlementDate').value=financeOpsToday();
    fillSettlementPayees();
    recalcSettlementAllocation();

    document.getElementById('bulkSettlementModal').classList.add('open');
  }

  function fillSettlementPayees(){
    const type=document.getElementById('settlementPayeeType')?.value||'';
    const select=document.getElementById('settlementPayeeId');
    if(!select)return;

    if(type==='Technician'){
      fillSelect(
        'settlementPayeeId',
        (BOOT.technicians||[]).map(t=>({
          value:t.Technician_ID,
          label:t.Full_Name||t.Technician_ID
        })),
        'Select technician'
      );
      return;
    }

    if(type==='Vendor'){
      fillSelect(
        'settlementPayeeId',
        (BOOT.suppliers||[]).map(s=>({
          value:s.Supplier_ID,
          label:s.Supplier_Name||s.Company_Name||s.Name||s.Supplier_ID
        })),
        'Select vendor'
      );
      return;
    }

    fillSelect('settlementPayeeId',[],'Choose payee type first');
  }

  function addSettlementAllocationRow(allocation={}){
    const box=document.getElementById('settlementAllocations');
    if(box.querySelector('.empty'))box.innerHTML='';

    SETTLEMENT_ALLOCATION_SEQ+=1;

    const row=document.createElement('div');
    row.className='card section settlement-allocation-row';
    row.style.marginBottom='10px';

    row.innerHTML=`
      <div class="section-head">
        <h3>Link ${SETTLEMENT_ALLOCATION_SEQ}</h3>
        <button type="button" class="btn small" onclick="removeSettlementAllocationRow(this)">Remove</button>
      </div>
      <div class="form-grid">
        <div><label class="required">Reference type</label>
          <select class="select" data-field="Reference_Type">
            <option>Repair</option>
            <option>Purchase</option>
          </select>
        </div>
        <div><label class="required">Repair / Purchase ID</label><input class="input" data-field="Reference_ID" value="${escAttr(allocation.Reference_ID||'')}" placeholder="REP-000123 or PUR-000123"></div>
        <div><label class="required">Amount (₦)</label><input class="input" type="number" min="1" step="1" data-field="Amount" value="${escAttr(allocation.Amount||'')}" oninput="recalcSettlementAllocation()"></div>
        <div><label>Notes</label><input class="input" data-field="Notes" value="${escAttr(allocation.Notes||'')}"></div>
      </div>`;

    box.appendChild(row);

    const type=row.querySelector('[data-field="Reference_Type"]');
    if(allocation.Reference_Type)type.value=allocation.Reference_Type;

    recalcSettlementAllocation();
  }

  function removeSettlementAllocationRow(button){
    button.closest('.settlement-allocation-row').remove();

    const box=document.getElementById('settlementAllocations');
    if(!box.querySelector('.settlement-allocation-row')){
      box.innerHTML=
        '<div class="empty" style="padding:14px">No links added yet.</div>';
    }

    recalcSettlementAllocation();
  }

  function settlementAllocationsPayload(){
    return [...document.querySelectorAll('.settlement-allocation-row')].map(row=>{
      const get=field=>row.querySelector(`[data-field="${field}"]`)?.value||'';
      return {
        Reference_Type:get('Reference_Type'),
        Reference_ID:get('Reference_ID'),
        Amount:get('Amount'),
        Notes:get('Notes')
      };
    });
  }

  function recalcSettlementAllocation(){
    const total=num(document.getElementById('settlementAmount')?.value);
    const allocated=[...document.querySelectorAll('.settlement-allocation-row')]
      .reduce((sum,row)=>sum+num(row.querySelector('[data-field="Amount"]')?.value),0);

    document.getElementById('settlementTotalView').textContent=money(total);
    document.getElementById('settlementAllocatedView').textContent=money(allocated);
    document.getElementById('settlementUnallocatedView').textContent=
      allocated>total
        ? `Over by ${money(allocated-total)}`
        : money(total-allocated);
  }

  async function submitBulkSettlement(e){
    e.preventDefault();
    const data=formObject(e.target);
    data.Allocations=settlementAllocationsPayload();

    showLoading(true);
    try{
      const result=await server('createBulkSettlement',data);
      closeModal('bulkSettlementModal');
      toast(`Recorded ${result.settlement.Settlement_ID}`);

      BOOT.dashboard=await server('refreshDashboard');

      if(CURRENT_PAGE==='finance'){
        await loadFinanceOperations();
      }

      if(CURRENT_PAGE==='repairs'){
        await loadRepairs();
      }

      if(CURRENT_PAGE==='purchases'){
        await loadPurchases();
      }
    }catch(err){
      toast(err.message,true);
    }finally{
      showLoading(false);
    }
  }

  function debouncedFinanceOpsLoad(){
    clearTimeout(FINANCE_OPS_TIMER);
    FINANCE_OPS_TIMER=setTimeout(loadFinanceOperations,300);
  }

  async function loadFinanceOperations(){
    try{
      const data=await server('getFinanceOperationsData',{
        expenseQ:document.getElementById('generalExpenseQ')?.value||'',
        settlementQ:document.getElementById('settlementQ')?.value||''
      });

      const s=data.summary||{};
      const kpis=document.getElementById('financeOpsKpis');

      if(kpis){
        kpis.innerHTML=`
          ${kpi("Today's credits",money(BOOT.dashboard.todayCredits),'Cash/revenue posted today')}
          ${kpi("Today's debits",money(BOOT.dashboard.todayDebits),'Cash paid today')}
          ${kpi('General expenses',money(s.generalExpenseTotal),'Recorded operating/general expenses')}
          ${kpi('Settlements',money(s.settlementTotal),`${s.settlementCount||0} bulk payment(s)`)}`;
      }

      renderGeneralExpenses(data.generalExpenses||[]);
      renderSettlements(data.settlements||[]);
    }catch(e){
      toast(e.message,true);
    }
  }

  function renderGeneralExpenses(rows){
    const box=document.getElementById('generalExpensesList');
    if(!box)return;

    if(!rows.length){
      box.innerHTML='<div class="empty">No general expenses recorded.</div>';
      return;
    }

    box.innerHTML=`<div class="table-wrap"><table>
      <thead><tr><th>Date</th><th>Expense</th><th>Payee</th><th>Link</th><th>Amount</th><th>Method</th></tr></thead>
      <tbody>${rows.map(row=>`<tr>
        <td>${dateOnly(row.Expense_Date)||'—'}</td>
        <td><b>${esc(row.Category)}</b><br><span class="muted">${esc(row.Description||'')}</span></td>
        <td>${esc(row.Payee||row.Supplier_ID||'—')}</td>
        <td>${row.Reference_ID?`${esc(row.Reference_Type)} · <b>${esc(row.Reference_ID)}</b>`:'—'}</td>
        <td class="money">${money(row.Amount)}</td>
        <td>${esc(row.Payment_Method||'')}</td>
      </tr>`).join('')}</tbody>
    </table></div>`;
  }

  function renderSettlements(rows){
    const box=document.getElementById('settlementsList');
    if(!box)return;

    if(!rows.length){
      box.innerHTML='<div class="empty">No settlements recorded.</div>';
      return;
    }

    box.innerHTML=`<div class="table-wrap"><table>
      <thead><tr><th>Date</th><th>Settlement</th><th>Payee</th><th>Linked records</th><th>Total</th><th>Allocated</th><th>Unallocated</th></tr></thead>
      <tbody>${rows.map(row=>`<tr>
        <td>${dateOnly(row.Settlement_Date)||'—'}</td>
        <td><b>${esc(row.Settlement_ID)}</b><br><span class="muted">${esc(row.Payment_Reference||row.Payment_Method||'')}</span></td>
        <td><span class="status">${esc(row.Payee_Type)}</span><br>${esc(row.Payee_Name||row.Payee_ID||'')}</td>
        <td>${(row.Allocations||[]).length
          ?(row.Allocations||[]).map(a=>`${esc(a.Reference_Type)} <b>${esc(a.Reference_ID)}</b> · ${money(a.Amount)}`).join('<br>')
          :'—'}</td>
        <td class="money">${money(row.Amount)}</td>
        <td class="money">${money(row.Allocated_Amount)}</td>
        <td class="money">${money(row.Unallocated_Amount)}</td>
      </tr>`).join('')}</tbody>
    </table></div>`;
  }

  function settlementAllocationTable(rows){
    if(!rows||!rows.length){
      return '<div class="empty" style="padding:16px">No bulk settlements linked to this record.</div>';
    }

    return `<div class="table-wrap"><table>
      <thead><tr><th>Date</th><th>Settlement</th><th>Payee type</th><th>Payee</th><th>Amount</th><th>Notes</th></tr></thead>
      <tbody>${rows.map(row=>`<tr>
        <td>${dateOnly(row.Settlement_Date)||'—'}</td>
        <td>${esc(row.Settlement_ID)}</td>
        <td>${esc(row.Payee_Type)}</td>
        <td>${esc(row.Payee_ID)}</td>
        <td class="money">${money(row.Amount)}</td>
        <td>${esc(row.Notes||'')}</td>
      </tr>`).join('')}</tbody>
    </table></div>`;
  }

'''
    html = html[:helper_anchor.start()] + helpers + html[helper_anchor.start():]

# ==========================================================
# Index.html — add settlement links to Repair detail
# ==========================================================

if "settlementAllocationTable(data.settlementAllocations||[])" not in html:
    # Insert immediately before Transactions heading in the repair detail
    # renderer. Use the first Transactions heading, which belongs to Repair.
    tx_heading = re.search(
        r'''(?is)<div[^>]*class=["'][^"']*section-head[^"']*["'][^>]*>\s*<h3>Transactions</h3>\s*</div>''',
        html,
    )

    if tx_heading:
        section = r'''<div style="margin-top:24px" class="section-head"><h3>Bulk settlements linked to repair</h3></div>
      ${settlementAllocationTable(data.settlementAllocations||[])}

      '''
        html = html[:tx_heading.start()] + section + html[tx_heading.start():]

# ==========================================================
# Index.html — add vendor settlement info to Purchase detail
# ==========================================================

if "data.settlementSummary" not in html:
    purchase_start = html.find("function renderPurchaseDetail")
    purchase_end = html.find("function purchaseItemsTable", purchase_start)

    if purchase_start >= 0 and purchase_end > purchase_start:
        region = html[purchase_start:purchase_end]

        # Add settlement summary into detail body before Purchased items.
        purchased_heading = re.search(
            r'''(?is)<div[^>]*class=["'][^"']*section-head[^"']*["'][^>]*>\s*<h3>Purchased items</h3>\s*</div>''',
            region,
        )

        if purchased_heading:
            settlement_block = r'''<div style="margin-top:24px" class="section-head"><h3>Vendor settlement</h3></div>
      <div class="detail-list" style="margin-bottom:14px">
        ${detail('Purchase items due',data.settlementSummary?money(data.settlementSummary.supplierDue):'—')}
        ${detail('Settled to vendor',data.settlementSummary?money(data.settlementSummary.supplierSettled):'—')}
        ${detail('Vendor balance',data.settlementSummary?money(data.settlementSummary.supplierBalance):'—')}
      </div>
      ${settlementAllocationTable(data.settlementAllocations||[])}

      '''
            region = (
                region[:purchased_heading.start()]
                + settlement_block
                + region[purchased_heading.start():]
            )
            html = html[:purchase_start] + region + html[purchase_end:]

# ==========================================================
# Final validation
# ==========================================================

required_code = [
    'generalExpenses: "General_Expenses"',
    'settlements: "Settlements"',
    'settlementAllocations: "Settlement_Allocations"',
    'General_Expenses: "GEX"',
    'Settlements: "STL"',
    'Settlement_Allocations: "STA"',
    'function createGeneralExpense(payload)',
    'function createBulkSettlement(payload)',
    'function getFinanceOperationsData(filters)',
    'function ensureFinanceOperationsSchema_(ss)',
    'addSettlementRepairCostsToFinanceMap_(financeSummary)',
]

required_html = [
    'id="generalExpenseModal"',
    'id="bulkSettlementModal"',
    'function openGeneralExpense()',
    'function openBulkSettlement()',
    'function renderGeneralExpenses(rows)',
    'function renderSettlements(rows)',
    'FIXXIR_FINANCE_OPS_UI_V1',
]

missing = [x for x in required_code if x not in code] + [
    x for x in required_html if x not in html
]

if missing:
    raise SystemExit(
        "ERROR: Patch validation failed. Missing: " + ", ".join(missing)
    )

code_path.write_text(code, encoding="utf-8")
html_path.write_text(html, encoding="utf-8")
PY

echo
echo "======================================================"
echo " Fixxir General Expenses + Bulk Settlements installed"
echo "======================================================"
echo
echo "Changed:"
echo "  $CODE_FILE"
echo "  $INDEX_FILE"
echo
echo "Backups:"
echo "  ${CODE_FILE}.before-finance-ops-v1.bak"
echo "  ${INDEX_FILE}.before-finance-ops-v1.bak"
echo
echo "Review:"
echo "  git diff --check"
echo "  git diff -- $CODE_FILE $INDEX_FILE"
echo
echo "Then deploy:"
echo "  npm run deploy"
echo
echo "New sheets are created automatically:"
echo "  - General_Expenses"
echo "  - Settlements"
echo "  - Settlement_Allocations"
echo
echo "Important:"
echo "  A bulk settlement produces ONE Finance_Ledger debit."
echo "  Its repair/purchase allocations do not create duplicate cash debits."
