#!/usr/bin/env bash
set -euo pipefail

CODE_FILE="${1:-Code.js}"
INDEX_FILE="${2:-Index.html}"

for f in "$CODE_FILE" "$INDEX_FILE"; do
  [[ -f "$f" ]] || { echo "ERROR: $f not found."; exit 1; }
done

if grep -q 'FIXXIR_BULK_WORKFLOW_V2' "$CODE_FILE" && \
   grep -q 'FIXXIR_BULK_WORKFLOW_UI_V2' "$INDEX_FILE"; then
  echo "Bulk workflow v2 is already installed."
  exit 0
fi

cp "$CODE_FILE" "${CODE_FILE}.before-bulk-workflow-v2.bak"
cp "$INDEX_FILE" "${INDEX_FILE}.before-bulk-workflow-v2.bak"

python3 - "$CODE_FILE" "$INDEX_FILE" <<'PY'
from pathlib import Path
import re
import sys

code_path = Path(sys.argv[1])
html_path = Path(sys.argv[2])

code = code_path.read_text(encoding="utf-8")
html = html_path.read_text(encoding="utf-8")

def fail(msg):
    raise SystemExit("ERROR: " + msg)

def replace_function(text, start_sig, next_sig, replacement, label):
    start = text.find(start_sig)
    if start < 0:
        fail(f"Could not locate {label}.")
    end = text.find(next_sig, start + len(start_sig))
    if end < 0:
        fail(f"Could not locate the end of {label}.")
    return text[:start] + replacement.rstrip() + "\n\n" + text[end:]

# --- Initialize sale/procurement linkage schema ---
if "ensureSaleProcurementSchema_(ss);" not in code:
    anchor = "  ensureProcurementSchema_(ss);\n"
    if anchor not in code:
        fail("initializeFixxir procurement schema anchor not found.")
    code = code.replace(anchor, anchor + "  ensureSaleProcurementSchema_(ss);\n", 1)

# --- Repair update cleanup ---
new_update_repair = r'''function updateRepair(payload) {
  assertAuthorized_();
  payload = payload || {};

  const repairId = clean_(payload.Repair_ID);
  if (!repairId) throw new Error("Repair_ID is required.");

  const existing = findById_(
    FIXXIR.sheets.repairs,
    "Repair_ID",
    repairId,
  );
  if (!existing) throw new Error("Repair not found: " + repairId);

  const allowed = [
    "Diagnosis",
    "Technician_ID",
    "Repair_Status",
    "Final_Amount",
    "QA_Status",
    "QA_Notes",
    "Date_Completed",
  ];

  const updates = {};
  allowed.forEach((key) => {
    if (!Object.prototype.hasOwnProperty.call(payload, key)) return;

    if (key === "Final_Amount") {
      updates[key] = numberOrBlank_(payload[key]);
    } else if (key === "Date_Completed") {
      updates[key] = parseDate_(payload[key]);
    } else {
      updates[key] = clean_(payload[key]);
    }
  });

  const nextStatus =
    Object.prototype.hasOwnProperty.call(updates, "Repair_Status")
      ? updates.Repair_Status
      : existing.Repair_Status;

  const nextFinal =
    Object.prototype.hasOwnProperty.call(updates, "Final_Amount")
      ? updates.Final_Amount
      : existing.Final_Amount;

  if (nextStatus === "Completed") {
    if (nextFinal === "" || nextFinal === null || nextFinal === undefined) {
      throw new Error(
        "Enter the final amount before marking this repair Completed.",
      );
    }

    if (!updates.Date_Completed && !existing.Date_Completed) {
      updates.Date_Completed = new Date();
    }
  }

  updates.Last_Updated = new Date();
  updates.Last_Updated_By = currentUser_();

  updateRecordById_(
    FIXXIR.sheets.repairs,
    "Repair_ID",
    repairId,
    updates,
  );

  return getRepair(repairId);
}'''

code = replace_function(
    code,
    "function updateRepair(payload)",
    "/* ---------------- Sales ---------------- */",
    new_update_repair,
    "updateRepair()",
)

# --- Sale detail backend ---
new_get_sale = r'''function getSale(salesId) {
  assertAuthorized_();
  ensureSalesSheets_(getSpreadsheet_());
  ensureSaleProcurementSchema_(getSpreadsheet_());

  const id = clean_(salesId);
  if (!id) throw new Error("Sales ID is required.");

  const order = findById_(FIXXIR.sheets.salesOrders, "Sales_ID", id);
  if (!order) throw new Error("Sale not found: " + id);

  const customer = order.Customer_ID
    ? findById_(FIXXIR.sheets.customers, "Customer_ID", order.Customer_ID)
    : null;

  const items = getRecords_(FIXXIR.sheets.salesItems)
    .filter((item) => item.Sales_ID === id);

  const transactions = getRecords_(FIXXIR.sheets.finance)
    .filter(
      (txn) =>
        txn.Sales_ID === id ||
        (txn.Reference_Type === "Sale" && txn.Reference_ID === id),
    )
    .sort((a, b) =>
      String(b.Date || "").localeCompare(String(a.Date || "")),
    );

  const paid = transactions
    .filter((txn) => txn.Transaction_Type === "Credit")
    .reduce((sum, txn) => sum + number_(txn.Amount), 0);

  const saleExpenses = transactions
    .filter((txn) => txn.Transaction_Type === "Debit")
    .reduce((sum, txn) => sum + number_(txn.Amount), 0);

  const total = number_(order.Total_Amount);
  let costTotal = 0;
  let allCostsKnown = true;
  let hasEstimatedCost = false;

  items.forEach((item) => {
    const status =
      clean_(item.Cost_Status) ||
      (hasValue_(item.Unit_Cost) ? "Known" : "Pending");

    if (status !== "Known") allCostsKnown = false;
    if (status === "Estimated") hasEstimatedCost = true;

    if (hasValue_(item.Cost_Total)) {
      costTotal += number_(item.Cost_Total);
    } else if (hasValue_(item.Unit_Cost)) {
      costTotal += number_(item.Unit_Cost) * number_(item.Quantity);
    }
  });

  const purchases = getRecords_(FIXXIR.sheets.purchases)
    .filter((purchase) => purchase.Sales_ID === id)
    .sort((a, b) =>
      String(b.Purchase_Date || b.Request_Date || "").localeCompare(
        String(a.Purchase_Date || a.Request_Date || ""),
      ),
    );

  const grossMargin = allCostsKnown ? total - costTotal : "";
  const contribution =
    allCostsKnown ? grossMargin - saleExpenses : "";

  return {
    order,
    customer,
    items,
    purchases,
    transactions,
    summary: {
      subtotal: number_(order.Subtotal),
      discount: number_(order.Discount_Amount),
      total,
      paid,
      balance: Math.max(0, total - paid),
      paymentStatus: salePaymentStatus_(total, paid),
      costTotal,
      saleExpenses,
      costStatus: allCostsKnown
        ? "Known"
        : hasEstimatedCost
          ? "Estimated / Pending"
          : "Pending",
      grossProfit: grossMargin,
      contribution,
    },
  };
}'''

code = replace_function(
    code,
    "function getSale(salesId)",
    "function createSale(payload)",
    new_get_sale,
    "getSale()",
)

# --- createSale auto procurement and default status ---
sale_start = code.find("function createSale(payload)")
sale_end = code.find("function postSalePayment(payload)", sale_start)
if sale_start < 0 or sale_end < 0:
    fail("Could not locate createSale().")

sale_region = code[sale_start:sale_end]
sale_region = sale_region.replace(
    'Sales_Status: clean_(payload.Sales_Status) || "Completed",',
    'Sales_Status: clean_(payload.Sales_Status) || "Pending Fulfilment",',
    1,
)

tail = '''  syncSalePaymentFields_(salesId);
  return getSale(salesId);
}'''
if tail not in sale_region:
    fail("createSale() return anchor not found.")

sale_region = sale_region.replace(
    tail,
    '''  syncSalePaymentFields_(salesId);

  if (clean_(payload.Sales_Status) !== "Cancelled") {
    ensureSaleProcurementForSale_(salesId);
  }

  return getSale(salesId);
}''',
    1,
)
code = code[:sale_start] + sale_region + code[sale_end:]

# --- Sale payment requires date ---
new_post_sale_payment = r'''function postSalePayment(payload) {
  assertAuthorized_();
  payload = payload || {};

  const salesId = clean_(payload.Sales_ID);
  if (!salesId) throw new Error("Sales_ID is required.");

  const sale = getSale(salesId);
  const amount = number_(payload.Amount);
  const paymentDate = parseDate_(payload.Date);

  if (!paymentDate) throw new Error("Payment date is required.");
  if (!(amount > 0))
    throw new Error("Payment amount must be greater than zero.");

  if (amount > sale.summary.balance) {
    throw new Error(
      "Payment cannot exceed the outstanding sale balance.",
    );
  }

  postFinance({
    Date: paymentDate,
    Transaction_Type: "Credit",
    Category: "Sales Revenue",
    Amount: amount,
    Payment_Method: payload.Payment_Method,
    Account: payload.Account || "Operating",
    Sales_ID: salesId,
    Customer_ID: sale.order.Customer_ID,
    Reference_Type: "Sale",
    Reference_ID: salesId,
    Description:
      clean_(payload.Description) || "Payment for " + salesId,
    Receipt_Reference: payload.Receipt_Reference,
    Notes: payload.Notes,
  });

  syncSalePaymentFields_(salesId);
  return getSale(salesId);
}'''

code = replace_function(
    code,
    "function postSalePayment(payload)",
    "function syncSalePaymentFields_",
    new_post_sale_payment,
    "postSalePayment()",
)

# --- Add sale finance/procurement backend ---
if "function ensureSaleProcurementForSale_(salesId)" not in code:
    anchor = "function postFinance(payload) {\n"
    if anchor not in code:
        fail("postFinance() anchor not found.")

    extra_backend = r'''/* FIXXIR_BULK_WORKFLOW_V2 */

/* ---------------- Sale finance / procurement linkage ---------------- */

function updateSale(payload) {
  assertAuthorized_();
  payload = payload || {};

  const salesId = clean_(payload.Sales_ID);
  if (!salesId) throw new Error("Sales_ID is required.");

  const order = findById_(
    FIXXIR.sheets.salesOrders,
    "Sales_ID",
    salesId,
  );
  if (!order) throw new Error("Sale not found: " + salesId);

  const items = getRecords_(FIXXIR.sheets.salesItems)
    .filter((item) => item.Sales_ID === salesId);

  const subtotal = items.reduce(
    (sum, item) => sum + number_(item.Line_Total),
    0,
  );

  const discount =
    payload.Discount_Amount === undefined
      ? number_(order.Discount_Amount)
      : number_(payload.Discount_Amount);

  if (discount < 0) throw new Error("Discount cannot be negative.");
  if (discount > subtotal)
    throw new Error("Discount cannot exceed subtotal.");

  const updates = {
    Subtotal: subtotal,
    Discount_Amount: discount,
    Total_Amount: subtotal - discount,
    Last_Updated: new Date(),
    Last_Updated_By: currentUser_(),
  };

  if (Object.prototype.hasOwnProperty.call(payload, "Sales_Status")) {
    updates.Sales_Status = clean_(payload.Sales_Status);
  }

  if (Object.prototype.hasOwnProperty.call(payload, "Date")) {
    const saleDate = parseDate_(payload.Date);
    if (!saleDate) throw new Error("Sale date is required.");
    updates.Date = saleDate;
  }

  if (Object.prototype.hasOwnProperty.call(payload, "Notes")) {
    updates.Notes = clean_(payload.Notes);
  }

  updateRecordById_(
    FIXXIR.sheets.salesOrders,
    "Sales_ID",
    salesId,
    updates,
  );

  if (updates.Sales_Status === "Cancelled") {
    getRecords_(FIXXIR.sheets.purchases)
      .filter(
        (purchase) =>
          purchase.Sales_ID === salesId &&
          purchase.Purchase_Status === "Sourcing" &&
          !purchase.Supplier_ID &&
          !purchase.Purchase_Date,
      )
      .forEach((purchase) => {
        updateRecordById_(
          FIXXIR.sheets.purchases,
          "Purchase_ID",
          purchase.Purchase_ID,
          {
            Purchase_Status: "Cancelled",
            Last_Updated: new Date(),
            Last_Updated_By: currentUser_(),
          },
        );
      });
  } else {
    ensureSaleProcurementForSale_(salesId);
  }

  syncSalePaymentFields_(salesId);
  return getSale(salesId);
}

function postSaleExpense(payload) {
  assertAuthorized_();
  payload = payload || {};

  const salesId = clean_(payload.Sales_ID);
  if (!salesId) throw new Error("Sales_ID is required.");

  const sale = getSale(salesId);
  const amount = number_(payload.Amount);
  const expenseDate = parseDate_(payload.Date);

  if (!expenseDate) throw new Error("Expense date is required.");
  if (!(amount > 0))
    throw new Error("Expense amount must be greater than zero.");

  postFinance({
    Date: expenseDate,
    Transaction_Type: "Debit",
    Category: clean_(payload.Category) || "Sale Expense",
    Amount: amount,
    Payment_Method: payload.Payment_Method,
    Account: payload.Account || "Operating",
    Sales_ID: salesId,
    Customer_ID: sale.order.Customer_ID,
    Supplier_ID: payload.Supplier_ID,
    Reference_Type: "Sale",
    Reference_ID: salesId,
    Description:
      clean_(payload.Description) || "Sale expense for " + salesId,
    Receipt_Reference: payload.Receipt_Reference,
    Notes: payload.Notes,
  });

  return getSale(salesId);
}

function ensureSaleProcurementSchema_(ss) {
  ss = ss || getSpreadsheet_();

  ensureSheetColumns_(
    ss,
    FIXXIR.sheets.purchases,
    ["Sales_ID", "Purchase_Source", "Request_Date"],
  );

  ensureSheetColumns_(
    ss,
    FIXXIR.sheets.purchaseItems,
    ["Sales_Item_ID"],
  );
}

function backfillSaleProcurement_() {
  ensureSaleProcurementSchema_(getSpreadsheet_());

  getRecords_(FIXXIR.sheets.salesOrders)
    .filter((sale) => sale.Sales_Status !== "Cancelled")
    .forEach((sale) => {
      ensureSaleProcurementForSale_(sale.Sales_ID);
    });
}

function ensureSaleProcurementForSale_(salesId) {
  ensureSaleProcurementSchema_(getSpreadsheet_());

  const sale = findById_(
    FIXXIR.sheets.salesOrders,
    "Sales_ID",
    salesId,
  );
  if (!sale || sale.Sales_Status === "Cancelled") return "";

  const existing = getRecords_(FIXXIR.sheets.purchases)
    .find(
      (purchase) =>
        purchase.Sales_ID === salesId &&
        purchase.Purchase_Source === "Sale",
    );

  if (existing) return existing.Purchase_ID;

  const saleItems = getRecords_(FIXXIR.sheets.salesItems)
    .filter(
      (item) =>
        item.Sales_ID === salesId &&
        clean_(item.Item_Source) !== "Inventory",
    );

  if (!saleItems.length) return "";

  const now = new Date();
  const purchaseId = generateId_(FIXXIR.sheets.purchases);

  appendRecord_(FIXXIR.sheets.purchases, {
    Purchase_ID: purchaseId,
    Sales_ID: salesId,
    Purchase_Source: "Sale",
    Request_Date: parseDate_(sale.Date) || now,
    Purchase_Date: "",
    Supplier_ID: "",
    Supplier_Reference: "",
    Purchase_Status: "Sourcing",
    Items_Subtotal: "",
    Additional_Costs: 0,
    Landed_Total: "",
    Cost_Status: "Pending",
    Created_At: now,
    Created_By: currentUser_(),
    Last_Updated: now,
    Last_Updated_By: currentUser_(),
    Notes: "Automatically created from " + salesId,
  });

  saleItems.forEach((item) => {
    appendRecord_(FIXXIR.sheets.purchaseItems, {
      Purchase_Item_ID: generateId_(FIXXIR.sheets.purchaseItems),
      Purchase_ID: purchaseId,
      Sales_Item_ID: item.Sales_Item_ID,
      Supplier_ID: "",
      Supplier_Item_ID: "",
      Product_ID: clean_(item.Product_ID),
      Item_Name: clean_(item.Product_Name),
      Quantity: number_(item.Quantity),
      Unit_Cost: "",
      Base_Total: "",
      Allocated_Expense: "",
      Landed_Total: "",
      Landed_Unit_Cost: "",
      Cost_Status: "Pending",
      IMEI_or_Serial: clean_(item.IMEI_or_Serial),
      Notes: "",
    });
  });

  return purchaseId;
}

function updatePurchaseHeader(payload) {
  assertAuthorized_();
  ensureSaleProcurementSchema_(getSpreadsheet_());
  payload = payload || {};

  const purchaseId = clean_(payload.Purchase_ID);
  if (!purchaseId) throw new Error("Purchase ID is required.");

  const purchase = findById_(
    FIXXIR.sheets.purchases,
    "Purchase_ID",
    purchaseId,
  );
  if (!purchase) throw new Error("Purchase not found: " + purchaseId);

  const status =
    clean_(payload.Purchase_Status) ||
    clean_(purchase.Purchase_Status) ||
    "Sourcing";

  const supplierId =
    Object.prototype.hasOwnProperty.call(payload, "Supplier_ID")
      ? clean_(payload.Supplier_ID)
      : clean_(purchase.Supplier_ID);

  const purchaseDate =
    Object.prototype.hasOwnProperty.call(payload, "Purchase_Date")
      ? parseDate_(payload.Purchase_Date)
      : parseDate_(purchase.Purchase_Date);

  if (supplierId) {
    if (
      !findById_(
        FIXXIR.sheets.suppliers,
        "Supplier_ID",
        supplierId,
      )
    ) {
      throw new Error("Selected vendor no longer exists.");
    }
  }

  if (!["Sourcing", "Cancelled"].includes(status)) {
    if (!supplierId)
      throw new Error("Select the vendor before moving out of Sourcing.");
    if (!purchaseDate)
      throw new Error(
        "Enter the actual purchase date before moving out of Sourcing.",
      );
  }

  updateRecordById_(
    FIXXIR.sheets.purchases,
    "Purchase_ID",
    purchaseId,
    {
      Supplier_ID: supplierId,
      Purchase_Date: purchaseDate || "",
      Purchase_Status: status,
      Supplier_Reference: clean_(payload.Supplier_Reference),
      Last_Updated: new Date(),
      Last_Updated_By: currentUser_(),
    },
  );

  const items = getRecords_(FIXXIR.sheets.purchaseItems)
    .filter((item) => item.Purchase_ID === purchaseId);

  items.forEach((item) => {
    updateRecordById_(
      FIXXIR.sheets.purchaseItems,
      "Purchase_Item_ID",
      item.Purchase_Item_ID,
      { Supplier_ID: supplierId },
    );

    if (supplierId) {
      const supplierItemId =
        clean_(item.Supplier_Item_ID) ||
        upsertSupplierCatalogFromPurchase_({
          Supplier_ID: supplierId,
          Product_ID: item.Product_ID,
          Supplier_Item_Name: item.Item_Name,
          Unit_Cost: item.Unit_Cost,
          Purchase_Date: purchaseDate || "",
        });

      if (!item.Supplier_Item_ID && supplierItemId) {
        updateRecordById_(
          FIXXIR.sheets.purchaseItems,
          "Purchase_Item_ID",
          item.Purchase_Item_ID,
          { Supplier_Item_ID: supplierItemId },
        );
      }
    }
  });

  recalculatePurchaseCosts_(purchaseId);
  return getPurchase(purchaseId);
}

function addPurchaseExpense(payload) {
  assertAuthorized_();
  ensureProcurementSchema_(getSpreadsheet_());
  payload = payload || {};

  const purchaseId = clean_(payload.Purchase_ID);
  if (!purchaseId) throw new Error("Purchase ID is required.");

  const purchase = findById_(
    FIXXIR.sheets.purchases,
    "Purchase_ID",
    purchaseId,
  );
  if (!purchase) throw new Error("Purchase not found: " + purchaseId);

  const amount = number_(payload.Amount);
  if (!(amount > 0))
    throw new Error("Shared cost amount must be greater than zero.");

  const allocationMethod =
    clean_(payload.Allocation_Method) || "By Value";

  if (!["By Value", "By Quantity"].includes(allocationMethod)) {
    throw new Error("Allocation must be By Value or By Quantity.");
  }

  appendRecord_(FIXXIR.sheets.purchaseExpenses, {
    Purchase_Expense_ID: generateId_(
      FIXXIR.sheets.purchaseExpenses,
    ),
    Purchase_ID: purchaseId,
    Purchase_Date: parseDate_(purchase.Purchase_Date) || "",
    Expense_Type: clean_(payload.Expense_Type) || "Other",
    Description: clean_(payload.Description),
    Amount: amount,
    Allocation_Method: allocationMethod,
    Payee: clean_(payload.Payee),
    Created_At: new Date(),
    Entered_By: currentUser_(),
    Notes: clean_(payload.Notes),
  });

  recalculatePurchaseCosts_(purchaseId);
  return getPurchase(purchaseId);
}

function syncSaleCostsFromPurchases_(salesId) {
  if (!salesId) return;

  ensureSaleProcurementSchema_(getSpreadsheet_());

  const saleItems = getRecords_(FIXXIR.sheets.salesItems)
    .filter((item) => item.Sales_ID === salesId);

  const purchaseMap = objectMap_(
    getRecords_(FIXXIR.sheets.purchases),
    "Purchase_ID",
  );

  const purchaseItems = getRecords_(FIXXIR.sheets.purchaseItems)
    .filter((item) => {
      if (!item.Sales_Item_ID) return false;
      const purchase = purchaseMap[item.Purchase_ID] || {};

      return (
        purchase.Sales_ID === salesId &&
        purchase.Purchase_Status !== "Sourcing" &&
        purchase.Purchase_Status !== "Cancelled" &&
        !!purchase.Supplier_ID &&
        !!purchase.Purchase_Date
      );
    });

  saleItems.forEach((saleItem) => {
    const linked = purchaseItems.filter(
      (item) => item.Sales_Item_ID === saleItem.Sales_Item_ID,
    );

    const requiredQty = number_(saleItem.Quantity);
    const linkedQty = linked.reduce(
      (sum, item) => sum + number_(item.Quantity),
      0,
    );

    const allKnown =
      linked.length > 0 &&
      linkedQty >= requiredQty &&
      linked.every(
        (item) =>
          item.Cost_Status === "Known" &&
          hasValue_(item.Landed_Total),
      );

    if (!allKnown) {
      updateRecordById_(
        FIXXIR.sheets.salesItems,
        "Sales_Item_ID",
        saleItem.Sales_Item_ID,
        {
          Unit_Cost: "",
          Cost_Total: "",
          Cost_Status: "Pending",
        },
      );
      return;
    }

    const landedTotal = linked.reduce(
      (sum, item) => sum + number_(item.Landed_Total),
      0,
    );

    const landedUnit =
      linkedQty > 0 ? landedTotal / linkedQty : 0;

    updateRecordById_(
      FIXXIR.sheets.salesItems,
      "Sales_Item_ID",
      saleItem.Sales_Item_ID,
      {
        Unit_Cost: landedUnit,
        Cost_Total: landedUnit * requiredQty,
        Cost_Status: "Known",
      },
    );
  });
}

'''
    code = code.replace(anchor, extra_backend + anchor, 1)

# --- Sync purchase landed cost back to sale ---
recalc_start = code.find("function recalculatePurchaseCosts_(purchaseId)")
recalc_end = code.find("function upsertSupplierCatalogFromPurchase_", recalc_start)
if recalc_start < 0 or recalc_end < 0:
    fail("Could not locate recalculatePurchaseCosts_().")

recalc_region = code[recalc_start:recalc_end]
if "syncSaleCostsFromPurchases_" not in recalc_region:
    tail = '''  updateRecordById_(
    FIXXIR.sheets.purchases,
    "Purchase_ID",
    purchaseId,
    {
      Items_Subtotal: subtotal,
      Additional_Costs: additionalCosts,
      Landed_Total: fullyKnown ? subtotal + additionalCosts : "",
      Cost_Status: fullyKnown ? "Known" : "Pending",
      Last_Updated: new Date(),
      Last_Updated_By: currentUser_(),
    },
  );
}'''
    if tail not in recalc_region:
        fail("Purchase recalculation tail anchor not found.")

    recalc_region = recalc_region.replace(
        tail,
        '''  updateRecordById_(
    FIXXIR.sheets.purchases,
    "Purchase_ID",
    purchaseId,
    {
      Items_Subtotal: subtotal,
      Additional_Costs: additionalCosts,
      Landed_Total: fullyKnown ? subtotal + additionalCosts : "",
      Cost_Status: fullyKnown ? "Known" : "Pending",
      Last_Updated: new Date(),
      Last_Updated_By: currentUser_(),
    },
  );

  const updatedPurchase = findById_(
    FIXXIR.sheets.purchases,
    "Purchase_ID",
    purchaseId,
  );

  if (updatedPurchase && updatedPurchase.Sales_ID) {
    syncSaleCostsFromPurchases_(updatedPurchase.Sales_ID);
  }
}''',
        1,
    )

code = code[:recalc_start] + recalc_region + code[recalc_end:]

# --- Purchase detail linked sale ---
purchase_start = code.find("function getPurchase(purchaseId)")
purchase_end = code.find("function createPurchase(payload)", purchase_start)
if purchase_start < 0 or purchase_end < 0:
    fail("Could not locate getPurchase().")

purchase_region = code[purchase_start:purchase_end]
if "linkedSale" not in purchase_region:
    return_anchor = "  return {\n    purchase,\n"
    if return_anchor not in purchase_region:
        fail("getPurchase() return anchor not found.")

    idx = purchase_region.find(return_anchor)
    purchase_region = (
        purchase_region[:idx]
        + '''  const linkedSale = purchase.Sales_ID
    ? findById_(
        FIXXIR.sheets.salesOrders,
        "Sales_ID",
        purchase.Sales_ID,
      )
    : null;

'''
        + purchase_region[idx:]
    )
    purchase_region = purchase_region.replace(
        return_anchor,
        "  return {\n    purchase,\n    linkedSale,\n",
        1,
    )

code = code[:purchase_start] + purchase_region + code[purchase_end:]

# --- Manual purchase optional sale linkage ---
create_purchase_start = code.find("function createPurchase(payload)")
create_purchase_end = code.find("function updatePurchaseItemCost(payload)", create_purchase_start)
if create_purchase_start < 0 or create_purchase_end < 0:
    fail("Could not locate createPurchase().")

cp_region = code[create_purchase_start:create_purchase_end]

if "Sales_ID: clean_(payload.Sales_ID)" not in cp_region:
    cp_region = cp_region.replace(
        '''    Purchase_ID: purchaseId,
    Purchase_Date: purchaseDate,
''',
        '''    Purchase_ID: purchaseId,
    Sales_ID: clean_(payload.Sales_ID),
    Purchase_Source: clean_(payload.Sales_ID) ? "Sale" : "Manual",
    Request_Date: parseDate_(payload.Request_Date) || purchaseDate,
    Purchase_Date: purchaseDate,
''',
        1,
    )

if "Sales_Item_ID: clean_(item.Sales_Item_ID)" not in cp_region:
    cp_region = cp_region.replace(
        '''      Purchase_Item_ID: generateId_(FIXXIR.sheets.purchaseItems),
      Purchase_ID: purchaseId,
''',
        '''      Purchase_Item_ID: generateId_(FIXXIR.sheets.purchaseItems),
      Purchase_ID: purchaseId,
      Sales_Item_ID: clean_(item.Sales_Item_ID),
''',
        1,
    )

code = code[:create_purchase_start] + cp_region + code[create_purchase_end:]

# --- Sales list economics ---
build_sales_start = code.find("function buildSalesRows_(filters)")
build_sales_end = code.find("function getSale(salesId)", build_sales_start)
if build_sales_start < 0 or build_sales_end < 0:
    fail("Could not locate buildSalesRows_().")

bs_region = code[build_sales_start:build_sales_end]
if "Sale_Expense_Calc" not in bs_region:
    bs_region = bs_region.replace(
        '''      Gross_Profit_Calc: itemSummary.allCostsKnown
        ? total - itemSummary.costTotal
        : "",
''',
        '''      Sale_Expense_Calc: finance.debits,
      Gross_Profit_Calc: itemSummary.allCostsKnown
        ? total - itemSummary.costTotal
        : "",
      Contribution_Calc: itemSummary.allCostsKnown
        ? total - itemSummary.costTotal - finance.debits
        : "",
''',
        1,
    )
code = code[:build_sales_start] + bs_region + code[build_sales_end:]

# --- Procurement page schema/backfill ---
proc_start = code.find("function getProcurementPageData(filters)")
proc_end = code.find("function createSupplier(payload)", proc_start)
if proc_start < 0 or proc_end < 0:
    fail("Could not locate getProcurementPageData().")

proc_region = code[proc_start:proc_end]
if "ensureSaleProcurementSchema_" not in proc_region:
    proc_region = proc_region.replace(
        '''  assertAuthorized_();
  ensureProcurementSchema_(getSpreadsheet_());
''',
        '''  assertAuthorized_();
  ensureProcurementSchema_(getSpreadsheet_());
  ensureSaleProcurementSchema_(getSpreadsheet_());
  backfillSaleProcurement_();
''',
        1,
    )
code = code[:proc_start] + proc_region + code[proc_end:]

# --- Dashboard backend ---
new_dashboard = r'''function getDashboardData_() {
  ensureSaleProcurementSchema_(getSpreadsheet_());
  backfillSaleProcurement_();

  const customers = getRecords_(FIXXIR.sheets.customers);
  const repairs = getRecords_(FIXXIR.sheets.repairs);
  const finance = getRecords_(FIXXIR.sheets.finance);
  const financeMap = buildRepairFinanceMap_(finance);

  const openRepairs = repairs.filter(
    (repair) =>
      !FIXXIR.closedRepairStatuses.includes(repair.Repair_Status),
  );

  const ready = repairs.filter(
    (repair) => repair.Repair_Status === "Ready for Pickup",
  );

  let outstanding = 0;

  repairs.forEach((repair) => {
    if (
      FIXXIR.closedRepairStatuses.includes(repair.Repair_Status) &&
      repair.Repair_Status !== "Completed"
    ) {
      return;
    }

    const revenue =
      number_(repair.Final_Amount) ||
      number_(repair.Quoted_Amount);

    const paid =
      (financeMap[repair.Repair_ID] || { credits: 0 }).credits;

    outstanding += Math.max(0, revenue - paid);
  });

  const today = Utilities.formatDate(
    new Date(),
    Session.getScriptTimeZone(),
    "yyyy-MM-dd",
  );

  let todayCredits = 0;
  let todayDebits = 0;

  finance.forEach((txn) => {
    if (dateKey_(txn.Date) !== today) return;

    if (txn.Transaction_Type === "Credit") {
      todayCredits += number_(txn.Amount);
    }

    if (txn.Transaction_Type === "Debit") {
      todayDebits += number_(txn.Amount);
    }
  });

  const customerMap = objectMap_(customers, "Customer_ID");

  const recentOpenRepairs = openRepairs
    .slice()
    .sort((a, b) =>
      repairDateKey_(b).localeCompare(repairDateKey_(a)),
    )
    .slice(0, 5)
    .map((repair) => ({
      Repair_ID: repair.Repair_ID,
      Repair_Date: repair.Repair_Date || repair.Date_Received,
      Customer_Name: customerMap[repair.Customer_ID]
        ? customerMap[repair.Customer_ID].Full_Name
        : "",
      Device: [repair.Brand, repair.Model].filter(Boolean).join(" "),
      Repair_Status: repair.Repair_Status,
    }));

  const recentSales = buildSalesRows_({})
    .filter((sale) => sale.Sales_Status !== "Cancelled")
    .slice(0, 5)
    .map((sale) => ({
      Sales_ID: sale.Sales_ID,
      Date: sale.Date,
      Customer_Name: sale.Customer_Name,
      Item_Summary: sale.Item_Summary,
      Sales_Status: sale.Sales_Status,
      Total_Amount: sale.Total_Amount,
      Amount_Paid_Calc: sale.Amount_Paid_Calc,
      Balance_Calc: sale.Balance_Calc,
      Payment_Status_Calc: sale.Payment_Status_Calc,
    }));

  return {
    totalCustomers: customers.length,
    openRepairs: openRepairs.length,
    readyForPickup: ready.length,
    outstandingRepairBalances: outstanding,
    todayCredits,
    todayDebits,
    netToday: todayCredits - todayDebits,
    recentOpenRepairs,
    recentSales,
  };
}'''

code = replace_function(
    code,
    "function getDashboardData_()",
    "/* ---------------- Repair / Purchase Notes ---------------- */",
    new_dashboard,
    "getDashboardData_()",
)

# ================= Frontend =================

# --- Repair edit modal ---
# Replace the Repair Date control by locating its ID, then replacing the
# containing <div>. This avoids depending on whitespace/formatting.
if 'id="editRepairDateView"' not in html:
    marker = 'id="editRepairDate"'
    pos = html.find(marker)

    if pos < 0:
        marker = "id='editRepairDate'"
        pos = html.find(marker)

    if pos < 0:
        fail("Could not locate Edit Repair date control.")

    div_start = html.rfind("<div", 0, pos)
    div_end = html.find("</div>", pos)

    if div_start < 0 or div_end < 0:
        fail("Could not locate Edit Repair date field container.")

    div_end += len("</div>")

    replacement = """<div>
                <label>Repair date</label>
                <div class="input" id="editRepairDateView" style="background:#f7f9fb;color:var(--muted)">—</div>
              </div>"""

    html = html[:div_start] + replacement + html[div_end:]

# Remove the old editable Notes field by locating editRepairNotes and removing
# the enclosing form-grid block.
marker = 'id="editRepairNotes"'
pos = html.find(marker)

if pos < 0:
    marker = "id='editRepairNotes'"
    pos = html.find(marker)

if pos >= 0:
    div_start = html.rfind("<div", 0, pos)
    div_end = html.find("</div>", pos)

    if div_start < 0 or div_end < 0:
        fail("Could not locate Edit Repair Notes field container.")

    div_end += len("</div>")
    html = html[:div_start] + html[div_end:]

# New Repair date optional.
html = re.sub(
    r'''<label class=["']required["']>Repair date</label>''',
    '<label>Repair date</label>',
    html,
    count=1,
)
html = re.sub(
    r'''(<input[^>]*id=["']repairDate["'][^>]*?)\srequired(?=[\s>])''',
    r'\1',
    html,
    count=1,
)

# Add status onchange.
html = html.replace(
    'id="editRepairStatus"\n                ></select>',
    'id="editRepairStatus"\n                  onchange="repairEditStatusChanged()"\n                ></select>',
    1,
)

# Populate readonly repair date.
status_assign = '''        document.getElementById("editRepairStatus").value =
          r.Repair_Status || "";
'''
if status_assign in html:
    html = html.replace(
        status_assign,
        status_assign +
        '''        document.getElementById("editRepairDateView").textContent =
          dateOnly(r.Repair_Date || r.Date_Received) || "—";
''',
        1,
    )

html = re.sub(
    r'''(?m)^[ \t]*document\.getElementById\(["']editRepairNotes["']\)\.value\s*=\s*
[ \t]*r\.Notes\s*\|\|\s*["'];\s*\n?''',
    "",
    html,
    count=1,
)
html = re.sub(
    r'''(?m)^[ \t]*document\.getElementById\(["']editRepairDate["']\)\.value\s*=.*?;\s*\n?''',
    "",
    html,
    count=1,
)

if "function repairEditStatusChanged()" not in html:
    anchor = "      async function submitRepairEdit(e) {"
    if anchor not in html:
        fail("submitRepairEdit() anchor not found.")
    html = html.replace(
        anchor,
        '''      function repairEditStatusChanged() {
        const status =
          document.getElementById("editRepairStatus")?.value || "";
        const completed =
          document.getElementById("editRepairCompleted");

        if (status === "Completed" && completed && !completed.value) {
          completed.value = localToday_();
        }
      }

''' + anchor,
        1,
    )

# --- Repair finance date ---
if 'id="financeDate"' not in html:
    finance_start = html.find('<div class="modal" id="financeModal">')
    finance_end = html.find('<div class="toast" id="toast">', finance_start)

    if finance_start < 0:
        fail("Finance modal not found.")
    if finance_end < 0:
        finance_end = len(html)

    finance_region = html[finance_start:finance_end]

    finance_amount = re.search(
        r'''(?is)(<div>\s*<label class=["']required["']>Amount \(₦\)</label.*?<input[^>]*name=["']Amount["'][^>]*>.*?</div>)''',
        finance_region,
    )

    if not finance_amount:
        fail("Finance Amount field not found.")

    date_field = '''
              <div>
                <label class="required">Payment / expense date</label>
                <input class="input" type="date" name="Date" id="financeDate" required />
              </div>'''

    insert_at = finance_start + finance_amount.end()
    html = html[:insert_at] + date_field + html[insert_at:]

finance_open_anchor = '''        populateStaticSelects();
        document.getElementById("financeType").value = type;
'''
if finance_open_anchor in html:
    html = html.replace(
        finance_open_anchor,
        '''        populateStaticSelects();
        document.getElementById("financeDate").value = localToday_();
        document.getElementById("financeType").value = type;
''',
        1,
    )

# --- Dashboard UI ---
dash_start = html.find("function renderDashboard(d)")
dash_end = html.find("function kpi(", dash_start)
if dash_start < 0 or dash_end < 0:
    fail("Dashboard renderer not found.")

new_dashboard_ui = r'''function renderDashboard(d) {
        document.getElementById("content").innerHTML = `
      <div class="toolbar">
        <div>
          <h2>Operations at a glance</h2>
          <div class="muted" style="margin-top:5px">Repairs, sales and customer balances.</div>
        </div>
        <div class="actions">
          <button class="btn primary" onclick="openNewRepair()">+ New Repair</button>
          <button class="btn dark" onclick="openNewSale()">+ New Sale</button>
          <button class="btn" onclick="refreshDashboardPage()">Refresh</button>
        </div>
      </div>

      <div class="grid kpis">
        ${kpi("Open repairs", d.openRepairs, "Active jobs in the pipeline")}
        ${kpi("Ready for pickup", d.readyForPickup, "Devices waiting for customers")}
        ${kpi("Outstanding repair balances", money(d.outstandingRepairBalances), "Uncollected repair revenue")}
      </div>

      <div class="grid" style="grid-template-columns:repeat(2,minmax(0,1fr));align-items:start">
        <div class="card section">
          <div class="section-head">
            <h3>Last 5 uncompleted repairs</h3>
            <button class="btn small" onclick="goRepairs()">View all</button>
          </div>
          ${repairMiniTable(d.recentOpenRepairs || [])}
        </div>

        <div class="card section">
          <div class="section-head">
            <h3>Last 5 sales</h3>
            <button class="btn small" onclick="goSales()">View all</button>
          </div>
          ${saleMiniTable(d.recentSales || [])}
        </div>
      </div>`;
      }

      function saleMiniTable(rows) {
        if (!rows.length) return '<div class="empty">No sales yet.</div>';

        return `<div class="table-wrap"><table>
          <thead><tr><th>Sale</th><th>Customer</th><th>Total</th><th>Balance</th></tr></thead>
          <tbody>${rows.map((sale) => `
            <tr class="clickable" onclick="openSale('${escAttr(sale.Sales_ID)}')">
              <td><b>${esc(sale.Sales_ID)}</b><br><span class="muted">${dateOnly(sale.Date)}</span></td>
              <td>${esc(sale.Customer_Name || "")}<br><span class="muted">${esc(sale.Item_Summary || "")}</span></td>
              <td class="money">${money(sale.Total_Amount)}</td>
              <td class="money">${money(sale.Balance_Calc)}</td>
            </tr>`).join("")}
          </tbody>
        </table></div>`;
      }

      function goSales() {
        const btn =
          document.querySelector('.nav button[data-page="sales"]');
        navigate("sales", btn);
      }

      '''

html = html[:dash_start] + new_dashboard_ui + html[dash_end:]

# --- New Sale defaults and cost sourcing ---
html = html.replace(
    '''<option selected>Completed</option>
                  <option>Draft</option>
                  <option>Cancelled</option>''',
    '''<option selected>Pending Fulfilment</option>
                  <option>Completed</option>
                  <option>Draft</option>
                  <option>Cancelled</option>''',
    1,
)

html = re.sub(
    r'''(?is)\s*<div>\s*
<label>Actual unit cost \(₦\)</label>\s*
<input[^>]*data-field=["']Unit_Cost["'][^>]*>\s*
<div[^>]*data-role=["']cost-label["'][^>]*>.*?</div>\s*
</div>''',
    "",
    html,
    count=1,
)

html = re.sub(
    r'''(?is)\s*if\s*\(\s*
!getRowField\(row,\s*["']Unit_Cost["']\)\s*&&\s*
hasDisplayValue\(item\.Default_Cost\)\s*
\)\s*\{\s*
setRowField\(row,\s*["']Unit_Cost["'],\s*item\.Default_Cost\);\s*
setRowField\(row,\s*["']Cost_Status["'],\s*["']Estimated["']\);\s*
updateSaleCostLabel\(row,\s*["']Estimated["']\);\s*
\}\s*''',
    "\n",
    html,
    count=1,
)

# --- Sale payment date ---
if 'id="salePaymentDate"' not in html:
    sale_payment_start = html.find('<div class="modal" id="salePaymentModal">')
    sale_payment_end = html.find('<div class="modal" id="saleCostModal">', sale_payment_start)

    if sale_payment_start < 0:
        fail("Sale payment modal not found.")
    if sale_payment_end < 0:
        sale_payment_end = len(html)

    sale_payment_region = html[sale_payment_start:sale_payment_end]

    payment_amount = re.search(
        r'''(?is)(<div>\s*<label class=["']required["']>Amount \(₦\)</label.*?id=["']salePaymentAmount["'].*?</div>)''',
        sale_payment_region,
    )

    if not payment_amount:
        fail("Sale payment Amount field not found.")

    date_field = '''
              <div>
                <label class="required">Payment date</label>
                <input class="input" type="date" name="Date" id="salePaymentDate" required />
              </div>'''

    insert_at = sale_payment_start + payment_amount.end()
    html = html[:insert_at] + date_field + html[insert_at:]

sale_payment_open_anchor = '''        document.getElementById("salePaymentTitle").textContent =
          `Record payment · ${CURRENT_SALE.order.Sales_ID}`;
'''
if sale_payment_open_anchor in html:
    html = html.replace(
        sale_payment_open_anchor,
        sale_payment_open_anchor +
        '''        document.getElementById("salePaymentDate").value =
          localToday_();
''',
        1,
    )

# --- Add modals ---
modal_insert = html.find('<div class="modal" id="financeModal">')
if modal_insert < 0:
    fail("Finance modal insertion point not found.")

if 'id="saleEditModal"' not in html:
    extra_modals = r'''<div class="modal" id="saleEditModal">
  <div class="modal-box" style="width:min(700px,100%)">
    <div class="modal-head"><h3 id="saleEditTitle">Edit Sale</h3><button class="close" onclick="closeModal('saleEditModal')">×</button></div>
    <form id="saleEditForm" onsubmit="submitSaleEdit(event)">
      <div class="modal-body">
        <input type="hidden" name="Sales_ID" id="saleEditId">
        <div class="form-grid">
          <div><label class="required">Sale date</label><input class="input" type="date" name="Date" id="saleEditDate" required></div>
          <div><label>Status</label><select class="select" name="Sales_Status" id="saleEditStatus"><option>Pending Fulfilment</option><option>Completed</option><option>Draft</option><option>Cancelled</option></select></div>
          <div><label>Discount (₦)</label><input class="input" type="number" min="0" step="1" name="Discount_Amount" id="saleEditDiscount"></div>
          <div class="full"><label>Sale note</label><textarea class="textarea" name="Notes" id="saleEditNotes"></textarea></div>
        </div>
      </div>
      <div class="modal-foot"><button type="button" class="btn" onclick="closeModal('saleEditModal')">Cancel</button><button class="btn primary" type="submit">Save changes</button></div>
    </form>
  </div>
</div>

<div class="modal" id="saleExpenseModal">
  <div class="modal-box" style="width:min(700px,100%)">
    <div class="modal-head"><h3 id="saleExpenseTitle">Record Sale Expense</h3><button class="close" onclick="closeModal('saleExpenseModal')">×</button></div>
    <form id="saleExpenseForm" onsubmit="submitSaleExpense(event)">
      <div class="modal-body">
        <input type="hidden" name="Sales_ID" id="saleExpenseSalesId">
        <div class="form-grid">
          <div><label class="required">Expense date</label><input class="input" type="date" name="Date" id="saleExpenseDate" required></div>
          <div><label class="required">Category</label><select class="select" name="Category" required><option>Customer Delivery</option><option>Packaging</option><option>Dispatch</option><option>Refund</option><option>Other Sale Expense</option></select></div>
          <div><label class="required">Amount (₦)</label><input class="input" type="number" min="1" step="1" name="Amount" required></div>
          <div><label class="required">Payment method</label><select class="select" name="Payment_Method" id="saleExpensePaymentMethod" required></select></div>
          <div><label>Vendor / payee</label><select class="select" name="Supplier_ID" id="saleExpenseSupplier"></select></div>
          <div><label>Account</label><input class="input" name="Account" value="Operating"></div>
          <div class="full"><label>Description</label><input class="input" name="Description"></div>
          <div><label>Receipt / bank reference</label><input class="input" name="Receipt_Reference"></div>
          <div class="full"><label>Notes</label><textarea class="textarea" name="Notes"></textarea></div>
        </div>
        <div class="muted" style="font-size:12px;margin-top:12px">Vendor acquisition cost belongs in the linked Purchase, not here. Use Sale Expense only for costs specific to serving this customer/sale.</div>
      </div>
      <div class="modal-foot"><button type="button" class="btn" onclick="closeModal('saleExpenseModal')">Cancel</button><button class="btn primary" type="submit">Record expense</button></div>
    </form>
  </div>
</div>

<div class="modal" id="purchaseEditModal">
  <div class="modal-box" style="width:min(720px,100%)">
    <div class="modal-head"><h3 id="purchaseEditTitle">Procurement Details</h3><button class="close" onclick="closeModal('purchaseEditModal')">×</button></div>
    <form id="purchaseEditForm" onsubmit="submitPurchaseEdit(event)">
      <div class="modal-body">
        <input type="hidden" name="Purchase_ID" id="purchaseEditId">
        <div class="form-grid">
          <div><label>Vendor</label><select class="select" name="Supplier_ID" id="purchaseEditSupplier"></select></div>
          <div><label>Purchase date</label><input class="input" type="date" name="Purchase_Date" id="purchaseEditDate"></div>
          <div><label>Status</label><select class="select" name="Purchase_Status" id="purchaseEditStatus"><option>Sourcing</option><option>Ordered</option><option>Part Received</option><option>Received</option><option>Cancelled</option></select></div>
          <div><label>Vendor invoice / reference</label><input class="input" name="Supplier_Reference" id="purchaseEditReference"></div>
        </div>
        <div class="muted" style="font-size:12px;margin-top:12px">Purchase Date is the actual vendor transaction date. It may remain blank while the request is still Sourcing.</div>
      </div>
      <div class="modal-foot"><button type="button" class="btn" onclick="closeModal('purchaseEditModal')">Cancel</button><button class="btn primary" type="submit">Save procurement</button></div>
    </form>
  </div>
</div>

<div class="modal" id="purchaseExpenseModal">
  <div class="modal-box" style="width:min(700px,100%)">
    <div class="modal-head"><h3 id="purchaseExpenseTitle">Add Shared Purchase Cost</h3><button class="close" onclick="closeModal('purchaseExpenseModal')">×</button></div>
    <form id="purchaseExpenseForm" onsubmit="submitPurchaseExpense(event)">
      <div class="modal-body">
        <input type="hidden" name="Purchase_ID" id="purchaseExpensePurchaseId">
        <div class="form-grid">
          <div><label>Type</label><select class="select" name="Expense_Type"><option>Logistics</option><option>Express Logistics</option><option>Clearing</option><option>Handling</option><option>Delivery</option><option>Packaging</option><option>Other</option></select></div>
          <div><label class="required">Amount (₦)</label><input class="input" type="number" min="1" step="1" name="Amount" required></div>
          <div><label>Allocate</label><select class="select" name="Allocation_Method"><option>By Value</option><option>By Quantity</option></select></div>
          <div><label>Payee</label><input class="input" name="Payee"></div>
          <div class="full"><label>Description</label><input class="input" name="Description"></div>
          <div class="full"><label>Notes</label><textarea class="textarea" name="Notes"></textarea></div>
        </div>
      </div>
      <div class="modal-foot"><button type="button" class="btn" onclick="closeModal('purchaseExpenseModal')">Cancel</button><button class="btn primary" type="submit">Add shared cost</button></div>
    </form>
  </div>
</div>

'''
    html = html[:modal_insert] + extra_modals + html[modal_insert:]

# --- Replace Sale detail/items table ---
sale_detail_start = html.find("function renderSaleDetail(data)")
sale_items_start = html.find("function saleItemsTable(rows)", sale_detail_start)
payment_badge_start = html.find("function salePaymentBadge", sale_items_start)
if sale_detail_start < 0 or sale_items_start < 0 or payment_badge_start < 0:
    fail("Sale detail renderer anchors not found.")

new_sale_detail = r'''function renderSaleDetail(data) {
        const order = data.order || {};
        const customer = data.customer || {};
        const summary = data.summary || {};
        const items = data.items || [];
        const purchases = data.purchases || [];

        document.getElementById("saleDetailTitle").textContent =
          `${order.Sales_ID || "Sale"} · ${customer.Full_Name || ""}`;

        document.getElementById("saleDetailBody").innerHTML = `
      <div class="repair-hero">
        <div>
          <div class="detail-list">
            ${detail("Customer", `${esc(customer.Full_Name || "")}<br><span class="muted">${esc(customer.Phone_Primary || "")}</span>`)}
            ${detail("Status", statusBadge(order.Sales_Status || ""))}
            ${detail("Sale date", dateOnly(order.Date) || "—")}
            ${detail("Payment", salePaymentBadge(summary.paymentStatus))}
            ${detail("Items", String(items.length))}
            ${detail("Created by", esc(order.Created_By || "—"))}
          </div>
          <div style="margin-top:18px;display:flex;gap:8px;flex-wrap:wrap">
            <button class="btn dark" onclick="openSaleEdit()">Edit Sale</button>
            ${summary.balance > 0 ? '<button class="btn primary" onclick="openSalePayment()">+ Customer Payment</button>' : ""}
            <button class="btn" onclick="openSaleExpense()">+ Sale Expense</button>
          </div>
        </div>
        <div class="finance-box">
          <div class="kpi-label" style="color:#bfd0df">Sale economics</div>
          <div class="finance-row"><span>Subtotal</span><b>${money(summary.subtotal)}</b></div>
          <div class="finance-row"><span>Discount</span><b>${money(summary.discount)}</b></div>
          <div class="finance-row big"><span>Total</span><span>${money(summary.total)}</span></div>
          <div class="finance-row"><span>Paid</span><b>${money(summary.paid)}</b></div>
          <div class="finance-row"><span>Balance</span><b>${money(summary.balance)}</b></div>
          <div class="finance-row"><span>Procurement / COGS</span><b>${summary.costStatus === "Known" ? money(summary.costTotal) : "Pending"}</b></div>
          <div class="finance-row"><span>Sale expenses</span><b>${money(summary.saleExpenses)}</b></div>
          <div class="finance-row"><span>Gross margin</span><b>${summary.costStatus === "Known" ? money(summary.grossProfit) : "Pending"}</b></div>
          <div class="finance-row big"><span>Contribution</span><span>${summary.costStatus === "Known" ? money(summary.contribution) : "Pending cost"}</span></div>
        </div>
      </div>

      <div style="margin-top:24px" class="section-head"><h3>Items</h3></div>
      ${saleItemsTable(items)}

      <div style="margin-top:24px" class="section-head"><h3>Procurement</h3></div>
      ${salePurchasesTable(purchases)}

      <div style="margin-top:24px" class="section-head"><h3>Payments & sale expenses</h3></div>
      ${transactionTable(data.transactions || [])}`;
      }

      function saleItemsTable(rows) {
        if (!rows.length) return '<div class="empty" style="padding:16px">No sale items.</div>';

        return `<div class="table-wrap"><table>
          <thead><tr><th>Item</th><th>Source</th><th>IMEI / Serial</th><th>Qty</th><th>Unit price</th><th>Procurement cost</th><th>Cost status</th><th>Total</th></tr></thead>
          <tbody>${rows.map((item) => `<tr>
            <td><b>${esc(item.Product_Name)}</b></td>
            <td>${esc(item.Item_Source || "Ad-hoc")}</td>
            <td>${esc(item.IMEI_or_Serial || "")}</td>
            <td>${esc(item.Quantity)}</td>
            <td class="money">${money(item.Unit_Price)}</td>
            <td class="money">${hasDisplayValue(item.Unit_Cost) ? money(item.Unit_Cost) : "Pending"}</td>
            <td>${esc(item.Cost_Status || "Pending")}</td>
            <td class="money">${money(item.Line_Total)}</td>
          </tr>`).join("")}</tbody>
        </table></div>`;
      }

      function salePurchasesTable(rows) {
        if (!rows.length) return '<div class="empty" style="padding:16px">No procurement request linked yet.</div>';

        return `<div class="table-wrap"><table>
          <thead><tr><th>Purchase</th><th>Vendor</th><th>Status</th><th>Date</th><th>Landed cost</th></tr></thead>
          <tbody>${rows.map((purchase) => `<tr class="clickable" onclick="openPurchase('${escAttr(purchase.Purchase_ID)}')">
            <td><b>${esc(purchase.Purchase_ID)}</b></td>
            <td>${esc(purchase.Supplier_ID || "Vendor pending")}</td>
            <td>${statusBadge(purchase.Purchase_Status || "Sourcing")}</td>
            <td>${dateOnly(purchase.Purchase_Date || purchase.Request_Date) || "—"}</td>
            <td class="money">${purchase.Landed_Total === "" ? "Pending" : money(purchase.Landed_Total)}</td>
          </tr>`).join("")}</tbody>
        </table></div>`;
      }

      '''

html = html[:sale_detail_start] + new_sale_detail + html[payment_badge_start:]

# --- Sale edit/expense functions ---
if "function openSaleEdit()" not in html:
    anchor = "      function openSalePayment() {"
    if anchor not in html:
        fail("openSalePayment() anchor not found.")

    funcs = r'''      function openSaleEdit() {
        if (!CURRENT_SALE) return;

        const order = CURRENT_SALE.order || {};
        document.getElementById("saleEditForm").reset();
        document.getElementById("saleEditId").value = order.Sales_ID || "";
        document.getElementById("saleEditTitle").textContent =
          `Edit ${order.Sales_ID || "Sale"}`;
        document.getElementById("saleEditDate").value = dateOnly(order.Date);
        document.getElementById("saleEditStatus").value =
          order.Sales_Status || "Pending Fulfilment";
        document.getElementById("saleEditDiscount").value =
          order.Discount_Amount || 0;
        document.getElementById("saleEditNotes").value = order.Notes || "";
        document.getElementById("saleEditModal").classList.add("open");
      }

      async function submitSaleEdit(e) {
        e.preventDefault();
        showLoading(true);
        try {
          CURRENT_SALE = await server("updateSale", formObject(e.target));
          closeModal("saleEditModal");
          renderSaleDetail(CURRENT_SALE);
          toast(`Updated ${CURRENT_SALE.order.Sales_ID}`);
          if (CURRENT_PAGE === "sales") await loadSales();
          BOOT.dashboard = await server("refreshDashboard");
        } catch (err) {
          toast(err.message, true);
        } finally {
          showLoading(false);
        }
      }

      function openSaleExpense() {
        if (!CURRENT_SALE) return;

        document.getElementById("saleExpenseForm").reset();
        document.getElementById("saleExpenseSalesId").value =
          CURRENT_SALE.order.Sales_ID;
        document.getElementById("saleExpenseTitle").textContent =
          `Sale expense · ${CURRENT_SALE.order.Sales_ID}`;
        document.getElementById("saleExpenseDate").value = localToday_();

        fillSelect(
          "saleExpensePaymentMethod",
          BOOT.settings.Payment_Method || [],
          "Select method",
        );

        fillSelect(
          "saleExpenseSupplier",
          (BOOT.suppliers || []).map((supplier) => ({
            value: supplier.Supplier_ID,
            label:
              supplier.Supplier_Name ||
              supplier.Company_Name ||
              supplier.Supplier_ID,
          })),
          "No vendor",
        );

        document.getElementById("saleExpenseModal").classList.add("open");
      }

      async function submitSaleExpense(e) {
        e.preventDefault();
        showLoading(true);
        try {
          CURRENT_SALE = await server(
            "postSaleExpense",
            formObject(e.target),
          );
          closeModal("saleExpenseModal");
          renderSaleDetail(CURRENT_SALE);
          toast("Sale expense recorded");
          if (CURRENT_PAGE === "sales") await loadSales();
          BOOT.dashboard = await server("refreshDashboard");
        } catch (err) {
          toast(err.message, true);
        } finally {
          showLoading(false);
        }
      }

'''
    html = html.replace(anchor, funcs + anchor, 1)

# --- Purchase page/status/detail ---
html = html.replace(
    '''<option value="">All statuses</option>
            <option>Received</option>''',
    '''<option value="">All statuses</option>
            <option>Sourcing</option><option>Received</option>''',
    1,
)

html = html.replace(
    '''<thead><tr><th>Purchase</th><th>Purchase date</th><th>Vendor</th><th>Status</th><th>Items</th><th>Shared costs</th><th>Landed total</th><th>Cost status</th></tr></thead>''',
    '''<thead><tr><th>Purchase</th><th>Purchase / request date</th><th>Linked sale</th><th>Vendor</th><th>Status</th><th>Items</th><th>Shared costs</th><th>Landed total</th><th>Cost status</th></tr></thead>''',
    1,
)

html = html.replace(
    '''        <td>${dateOnly(p.Purchase_Date)||'—'}</td>
        <td>${esc(p.Supplier_Name||p.Supplier_ID||'')}</td>''',
    '''        <td>${dateOnly(p.Purchase_Date||p.Request_Date)||'—'}</td>
        <td>${p.Sales_ID?`<b>${esc(p.Sales_ID)}</b>`:'—'}</td>
        <td>${esc(p.Supplier_Name||p.Supplier_ID||'Vendor pending')}</td>''',
    1,
)

purchase_render_start = html.find("function renderPurchaseDetail(data)")
purchase_table_start = html.find("function purchaseItemsTable(rows)", purchase_render_start)
if purchase_render_start < 0 or purchase_table_start < 0:
    fail("renderPurchaseDetail() not found.")

pr_region = html[purchase_render_start:purchase_table_start]
if "openPurchaseEdit()" not in pr_region:
    pr_region = pr_region.replace(
        "${detail('Vendor',esc(s.Supplier_Name||p.Supplier_ID||'—'))}",
        "${detail('Vendor',esc(s.Supplier_Name||p.Supplier_ID||'Vendor pending'))}\n            ${detail('Linked sale',p.Sales_ID?`<button class=\"btn small\" onclick=\"openSale('${escAttr(p.Sales_ID)}')\">${esc(p.Sales_ID)}</button>`:'—')}",
        1,
    )

    finance_anchor = '''        <div class="finance-box">'''
    if finance_anchor not in pr_region:
        fail("Purchase finance-box anchor not found.")

    pr_region = pr_region.replace(
        finance_anchor,
        '''        <div style="margin-top:18px;display:flex;gap:8px;flex-wrap:wrap">
          <button class="btn dark" onclick="openPurchaseEdit()">Edit Procurement</button>
          <button class="btn" onclick="openPurchaseExpense()">+ Shared Cost</button>
        </div>
        <div class="finance-box">''',
        1,
    )

html = html[:purchase_render_start] + pr_region + html[purchase_table_start:]

if "function openPurchaseEdit()" not in html:
    anchor = "  function purchaseItemsTable(rows)"
    if anchor not in html:
        fail("purchaseItemsTable() anchor not found.")

    funcs = r'''  function openPurchaseEdit(){
    if(!CURRENT_PURCHASE)return;

    const p=CURRENT_PURCHASE.purchase||{};
    document.getElementById('purchaseEditForm').reset();
    document.getElementById('purchaseEditId').value=p.Purchase_ID||'';
    document.getElementById('purchaseEditTitle').textContent=
      `Procurement · ${p.Purchase_ID||''}`;

    fillSelect(
      'purchaseEditSupplier',
      (BOOT.suppliers||[]).map(s=>({
        value:s.Supplier_ID,
        label:s.Supplier_Name||s.Supplier_ID
      })),
      'Vendor pending'
    );

    document.getElementById('purchaseEditSupplier').value=p.Supplier_ID||'';
    document.getElementById('purchaseEditDate').value=dateOnly(p.Purchase_Date);
    document.getElementById('purchaseEditStatus').value=p.Purchase_Status||'Sourcing';
    document.getElementById('purchaseEditReference').value=p.Supplier_Reference||'';

    document.getElementById('purchaseEditModal').classList.add('open');
  }

  async function submitPurchaseEdit(e){
    e.preventDefault();
    showLoading(true);
    try{
      CURRENT_PURCHASE=await server('updatePurchaseHeader',formObject(e.target));
      closeModal('purchaseEditModal');
      renderPurchaseDetail(CURRENT_PURCHASE);
      toast('Procurement updated');
      if(CURRENT_PAGE==='purchases')await loadPurchases();

      if(CURRENT_PURCHASE.purchase?.Sales_ID){
        CURRENT_SALE=await server('getSale',CURRENT_PURCHASE.purchase.Sales_ID);
      }
    }catch(err){
      toast(err.message,true);
    }finally{
      showLoading(false);
    }
  }

  function openPurchaseExpense(){
    if(!CURRENT_PURCHASE)return;

    document.getElementById('purchaseExpenseForm').reset();
    document.getElementById('purchaseExpensePurchaseId').value=
      CURRENT_PURCHASE.purchase.Purchase_ID;
    document.getElementById('purchaseExpenseTitle').textContent=
      `Shared cost · ${CURRENT_PURCHASE.purchase.Purchase_ID}`;
    document.getElementById('purchaseExpenseModal').classList.add('open');
  }

  async function submitPurchaseExpense(e){
    e.preventDefault();
    showLoading(true);
    try{
      CURRENT_PURCHASE=await server('addPurchaseExpense',formObject(e.target));
      closeModal('purchaseExpenseModal');
      renderPurchaseDetail(CURRENT_PURCHASE);
      toast('Shared purchase cost added');
      if(CURRENT_PAGE==='purchases')await loadPurchases();
    }catch(err){
      toast(err.message,true);
    }finally{
      showLoading(false);
    }
  }

'''
    html = html.replace(anchor, funcs + anchor, 1)

# --- Async stale page hardening ---
html = html.replace(
    '''          const data = await server("refreshDashboard");
          BOOT.dashboard = data;
          renderDashboard(data);''',
    '''          const data = await server("refreshDashboard");
          BOOT.dashboard = data;
          if (CURRENT_PAGE !== "dashboard") return;
          renderDashboard(data);''',
    1,
)

html = html.replace(
    '''          const rows = await server("listRepairs", { q, status });
          const box = document.getElementById("repairsList");''',
    '''          const rows = await server("listRepairs", { q, status });
          if (CURRENT_PAGE !== "repairs") return;
          const box = document.getElementById("repairsList");
          if (!box) return;''',
    1,
)

html = html.replace(
    '''          const data = await server("getSalesPageData", {
            q,
            status,
            paymentStatus,
          });
          const s = data.summary || {};''',
    '''          const data = await server("getSalesPageData", {
            q,
            status,
            paymentStatus,
          });
          if (CURRENT_PAGE !== "sales") return;
          const s = data.summary || {};''',
    1,
)

html = html.replace(
    '''          const box = document.getElementById("salesList");
          const rows = data.sales || [];''',
    '''          const box = document.getElementById("salesList");
          if (!box) return;
          const rows = data.sales || [];''',
    1,
)

html = html.replace(
    '''      const data=await server('getProcurementPageData',{
        q:document.getElementById('purchaseQ')?.value||'',
        supplierId:document.getElementById('purchaseSupplierFilter')?.value||'',
        status:document.getElementById('purchaseStatusFilter')?.value||'',
        catalogQ:document.getElementById('catalogQ')?.value||''
      });

      BOOT.suppliers=data.suppliers||BOOT.suppliers||[];''',
    '''      const data=await server('getProcurementPageData',{
        q:document.getElementById('purchaseQ')?.value||'',
        supplierId:document.getElementById('purchaseSupplierFilter')?.value||'',
        status:document.getElementById('purchaseStatusFilter')?.value||'',
        catalogQ:document.getElementById('catalogQ')?.value||''
      });

      if(CURRENT_PAGE!=='purchases')return;
      BOOT.suppliers=data.suppliers||BOOT.suppliers||[];''',
    1,
)

html = html.replace(
    '''          const rows = await server("listQuotes", {});
          if (!rows.length) {''',
    '''          const rows = await server("listQuotes", {});
          if (CURRENT_PAGE !== "sales") return;
          if (!document.getElementById("quotesList")) return;
          if (!rows.length) {''',
    1,
)

html = html.replace(
    '''      const data=await server('getFinanceOperationsData',{
        expenseQ:document.getElementById('generalExpenseQ')?.value||'',
        settlementQ:document.getElementById('settlementQ')?.value||''
      });

      const s=data.summary||{};''',
    '''      const data=await server('getFinanceOperationsData',{
        expenseQ:document.getElementById('generalExpenseQ')?.value||'',
        settlementQ:document.getElementById('settlementQ')?.value||''
      });

      if(CURRENT_PAGE!=='finance')return;
      const s=data.summary||{};''',
    1,
)

# Marker.
if "FIXXIR_BULK_WORKFLOW_UI_V2" not in html:
    html = html.replace(
        "</style>",
        "  /* FIXXIR_BULK_WORKFLOW_UI_V2 */\n  </style>",
        1,
    )

# Validation.
required_code = [
    "FIXXIR_BULK_WORKFLOW_V2",
    "function updateSale(payload)",
    "function postSaleExpense(payload)",
    "function ensureSaleProcurementForSale_(salesId)",
    "function updatePurchaseHeader(payload)",
    "function addPurchaseExpense(payload)",
    "function syncSaleCostsFromPurchases_(salesId)",
    "recentOpenRepairs",
    "recentSales",
]
required_html = [
    "FIXXIR_BULK_WORKFLOW_UI_V2",
    'id="saleEditModal"',
    'id="saleExpenseModal"',
    'id="purchaseEditModal"',
    'id="purchaseExpenseModal"',
    'id="financeDate"',
    'id="salePaymentDate"',
    "function openSaleEdit()",
    "function openSaleExpense()",
    "function openPurchaseEdit()",
    "function saleMiniTable(rows)",
]

missing = [x for x in required_code if x not in code] + [x for x in required_html if x not in html]
if missing:
    fail("Patch validation failed. Missing: " + ", ".join(missing))

repair_edit_start = html.find('id="repairEditModal"')
repair_form_end = html.find('</form>', repair_edit_start)

if repair_edit_start < 0 or repair_form_end < 0:
    fail("Could not validate Repair Edit form.")

repair_edit_region = html[repair_edit_start:repair_form_end]

for forbidden in ['name="Repair_Date"', 'id="editRepairNotes"']:
    if forbidden in repair_edit_region:
        fail("Repair edit cleanup failed; still found " + forbidden)

if 'id="editRepairDateView"' not in repair_edit_region:
    fail("Repair date read-only display was not installed.")

code_path.write_text(code, encoding="utf-8")
html_path.write_text(html, encoding="utf-8")
PY

echo
echo "======================================================"
echo " Fixxir bulk workflow update applied"
echo "======================================================"
echo
echo "Review:"
echo "  git diff --check"
echo "  git diff -- Code.js Index.html"
echo
echo "Then deploy:"
echo "  npm run deploy"
echo
echo "New behavior:"
echo "  - Existing/new sales get a linked Sourcing purchase."
echo "  - Vendor/date/costs are completed later from Purchase detail."
echo "  - Landed cost flows back to the linked sale."
echo "  - Sale-specific expenses remain separate from procurement cost."
echo "  - Payment/expense dates are explicit."
echo "  - Dashboard shows 5 active repairs + 5 latest sales."
