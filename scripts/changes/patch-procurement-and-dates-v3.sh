#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# Fixxir Procurement + Transaction Date Patch v3
# ==========================================================
#
# Adds:
#   - Supplier-specific catalog
#   - Purchases
#   - Purchase items
#   - Purchase shared expenses (logistics, clearing, etc.)
#   - Landed-cost allocation
#   - Vendor price history / price-change tracking
#   - Vendor comparison/search
#   - Repair_Date separate from Created_At
#   - Purchase_Date separate from Created_At
#   - Legacy Repair_Date migration from Date_Received
#
# Compatible with the current Fixxir Sales build and designed to
# tolerate the earlier UI-cleanup / flexible-sales patches.
#
# Run from the repository root:
#   chmod +x patch-procurement-and-dates.sh
#   ./patch-procurement-and-dates.sh
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

if grep -q 'FIXXIR_PROCUREMENT_V1' "$CODE_FILE" && \
   grep -q 'FIXXIR_PROCUREMENT_UI_V1' "$INDEX_FILE"; then
  echo "Procurement/date patch is already installed."
  exit 0
fi

cp "$CODE_FILE" "${CODE_FILE}.before-procurement-v1.bak"
cp "$INDEX_FILE" "${INDEX_FILE}.before-procurement-v1.bak"

python3 - "$CODE_FILE" "$INDEX_FILE" <<'PY'
from pathlib import Path
import re
import sys

code_path = Path(sys.argv[1])
html_path = Path(sys.argv[2])

code = code_path.read_text(encoding="utf-8")
html = html_path.read_text(encoding="utf-8")

def replace_once(text, old, new, label):
    if old not in text:
        raise SystemExit(f"ERROR: Could not find anchor for {label}. Backups were created; source files were not written.")
    return text.replace(old, new, 1)

# ==========================================================
# Code.js — schema registration
# ==========================================================

if 'supplierCatalog: "Supplier_Catalog"' not in code:
    code = replace_once(
        code,
        '    suppliers: "Suppliers",\n',
        '    suppliers: "Suppliers",\n'
        '    supplierCatalog: "Supplier_Catalog",\n'
        '    purchases: "Purchases",\n'
        '    purchaseItems: "Purchase_Items",\n'
        '    purchaseExpenses: "Purchase_Expenses",\n',
        "procurement sheet names",
    )

if 'Supplier_Catalog: "VIT"' not in code:
    code = replace_once(
        code,
        '    Suppliers: "SUP",\n',
        '    Suppliers: "SUP",\n'
        '    Supplier_Catalog: "VIT",\n'
        '    Purchases: "PUR",\n'
        '    Purchase_Items: "PIT",\n'
        '    Purchase_Expenses: "PEX",\n',
        "procurement ID prefixes",
    )

# Add schema constants before doGet(), regardless of whether flexible-sales
# added more constants between Sales Items and doGet.
if "const FIXXIR_PURCHASE_HEADERS" not in code:
    idx = code.find("function doGet()")
    if idx < 0:
        raise SystemExit("ERROR: doGet() anchor not found.")

    constants = r'''
/* FIXXIR_PROCUREMENT_V1 */

const FIXXIR_SUPPLIER_REQUIRED_HEADERS = Object.freeze([
  "Supplier_ID",
  "Supplier_Name",
  "Contact_Name",
  "Phone",
  "Email",
  "Address",
  "Status",
  "Date_Created",
  "Notes",
]);

const FIXXIR_SUPPLIER_CATALOG_HEADERS = Object.freeze([
  "Supplier_Item_ID",
  "Supplier_ID",
  "Product_ID",
  "Supplier_Item_Name",
  "Brand",
  "Model",
  "Variant",
  "Last_Quoted_Price",
  "Last_Quote_Date",
  "Last_Purchase_Price",
  "Last_Purchase_Date",
  "Availability",
  "Status",
  "Created_At",
  "Last_Updated",
  "Notes",
]);

const FIXXIR_PURCHASE_HEADERS = Object.freeze([
  "Purchase_ID",
  "Purchase_Date",
  "Supplier_ID",
  "Supplier_Reference",
  "Purchase_Status",
  "Items_Subtotal",
  "Additional_Costs",
  "Landed_Total",
  "Cost_Status",
  "Created_At",
  "Created_By",
  "Last_Updated",
  "Notes",
]);

const FIXXIR_PURCHASE_ITEM_HEADERS = Object.freeze([
  "Purchase_Item_ID",
  "Purchase_ID",
  "Supplier_ID",
  "Supplier_Item_ID",
  "Product_ID",
  "Item_Name",
  "Quantity",
  "Unit_Cost",
  "Base_Total",
  "Allocated_Expense",
  "Landed_Total",
  "Landed_Unit_Cost",
  "Cost_Status",
  "IMEI_or_Serial",
  "Notes",
]);

const FIXXIR_PURCHASE_EXPENSE_HEADERS = Object.freeze([
  "Purchase_Expense_ID",
  "Purchase_ID",
  "Purchase_Date",
  "Expense_Type",
  "Description",
  "Amount",
  "Allocation_Method",
  "Payee",
  "Finance_Transaction_ID",
  "Created_At",
  "Entered_By",
  "Notes",
]);

'''
    code = code[:idx] + constants + code[idx:]

# ==========================================================
# Initialization: create/migrate new schema before required-sheet check
# ==========================================================

init_anchor_candidates = [
    "  ensureContactsSheet_(ss);\n  ensureSalesSheets_(ss);\n",
    "  ensureContactsSheet_(ss);\n",
]

if "ensureProcurementSchema_(ss);" not in code:
    for anchor in init_anchor_candidates:
        if anchor in code:
            replacement = anchor + "  ensureProcurementSchema_(ss);\n  ensureRepairDateSchema_(ss);\n"
            code = code.replace(anchor, replacement, 1)
            break
    else:
        raise SystemExit("ERROR: Could not find initialization schema anchor.")

# Bootstrap supplier list for the Purchases UI.
if "suppliers: getActiveSuppliers_()" not in code:
    code = replace_once(
        code,
        "    technicians: getActiveTechnicians_(),\n",
        "    technicians: getActiveTechnicians_(),\n"
        "    suppliers: getActiveSuppliers_(),\n",
        "bootstrap supplier list",
    )

# ==========================================================
# Repair_Date vs Created_At
# ==========================================================

# New repairs: transaction date and creation timestamp are different facts.
if "Repair_Date: parseDate_(payload.Repair_Date)" not in code:
    old = '''  appendRecord_(FIXXIR.sheets.repairs, {
    Repair_ID: id,
    Date_Received: now,
'''
    new = '''  const repairDate = parseDate_(payload.Repair_Date) || now;

  appendRecord_(FIXXIR.sheets.repairs, {
    Repair_ID: id,
    Repair_Date: repairDate,
    Date_Received: repairDate,
    Created_At: now,
'''
    code = replace_once(code, old, new, "createRepair Repair_Date")

# Permit correcting imported/historical Repair_Date.
if '"Repair_Date",' not in code[code.find("function updateRepair"):code.find("/* ---------------- Sales ---------------- */")]:
    code = replace_once(
        code,
        '  const allowed = [\n',
        '  const allowed = [\n    "Repair_Date",\n',
        "updateRepair Repair_Date",
    )

# Treat Repair_Date as a date in updateRepair.
old_date_parse = '      else if (["Expected_Completion", "Date_Completed"].includes(k))\n'
if old_date_parse in code and '"Repair_Date", "Expected_Completion", "Date_Completed"' not in code:
    code = code.replace(
        old_date_parse,
        '      else if (["Repair_Date", "Expected_Completion", "Date_Completed"].includes(k))\n',
        1,
    )
elif '["Date_Completed"].includes(k)' in code and '"Repair_Date", "Date_Completed"' not in code:
    code = code.replace(
        '["Date_Completed"].includes(k)',
        '["Repair_Date", "Date_Completed"].includes(k)',
        1,
    )

# Repair list ordering: actual repair transaction date first.
code = code.replace(
    '''  rows.sort((a, b) =>
    String(b.Date_Received || "").localeCompare(String(a.Date_Received || "")),
  );''',
    '''  rows.sort((a, b) =>
    repairDateKey_(b).localeCompare(repairDateKey_(a)),
  );''',
    1,
)

# Dashboard recent repairs should expose/sort by Repair_Date.
code = code.replace(
    '''    .sort((a, b) =>
      String(b.Date_Received || "").localeCompare(
        String(a.Date_Received || ""),
      ),
    )''',
    '''    .sort((a, b) =>
      repairDateKey_(b).localeCompare(repairDateKey_(a)),
    )''',
    1,
)

recent_map_anchor = '''      Repair_ID: r.Repair_ID,
      Date_Received: r.Date_Received,
'''
if recent_map_anchor in code and "Repair_Date: r.Repair_Date || r.Date_Received" not in code:
    code = code.replace(
        recent_map_anchor,
        '''      Repair_ID: r.Repair_ID,
      Repair_Date: r.Repair_Date || r.Date_Received,
      Date_Received: r.Date_Received,
''',
        1,
    )

# ==========================================================
# Procurement backend
# ==========================================================

if "function createPurchase(payload)" not in code:
    backend_anchor = "function postFinance(payload) {\n"
    if backend_anchor not in code:
        backend_anchor = "/* ---------------- Dashboard ---------------- */\n"
    if backend_anchor not in code:
        raise SystemExit("ERROR: Could not find backend insertion anchor.")

    procurement_backend = r'''
/* ---------------- Procurement / Vendor Catalog ---------------- */

function getProcurementPageData(filters) {
  assertAuthorized_();
  ensureProcurementSchema_(getSpreadsheet_());

  filters = filters || {};
  const purchases = listPurchases(filters);
  const catalog = listSupplierCatalog({
    q: filters.catalogQ || filters.q || "",
    supplierId: filters.supplierId || "",
  });

  const allPurchases = listPurchases({});
  const active = allPurchases.filter(
    (p) => String(p.Purchase_Status || "") !== "Cancelled",
  );

  return {
    purchases,
    catalog,
    suppliers: getActiveSuppliers_(),
    summary: {
      purchases: active.length,
      knownPurchaseValue: active.reduce(
        (sum, p) => sum + number_(p.Landed_Total),
        0,
      ),
      additionalCosts: active.reduce(
        (sum, p) => sum + number_(p.Additional_Costs),
        0,
      ),
      pendingCosts: active.filter((p) => p.Cost_Status === "Pending").length,
      vendors: new Set(
        active.map((p) => p.Supplier_ID).filter(Boolean),
      ).size,
    },
  };
}

function createSupplier(payload) {
  assertAuthorized_();
  ensureProcurementSchema_(getSpreadsheet_());
  payload = payload || {};

  const name = clean_(
    payload.Supplier_Name ||
    payload.Company_Name ||
    payload.Name
  );
  if (!name) throw new Error("Vendor name is required.");

  const existing = getRecords_(FIXXIR.sheets.suppliers).find(
    (s) => getSupplierDisplayName_(s).toLowerCase() === name.toLowerCase(),
  );
  if (existing) return normalizeSupplier_(existing);

  const id = generateId_(FIXXIR.sheets.suppliers);
  const now = new Date();

  appendRecord_(FIXXIR.sheets.suppliers, {
    Supplier_ID: id,
    Supplier_Name: name,
    Company_Name: name,
    Name: name,
    Contact_Name: clean_(payload.Contact_Name),
    Phone: clean_(payload.Phone),
    Email: clean_(payload.Email),
    Address: clean_(payload.Address),
    Status: "Active",
    Date_Created: now,
    Notes: clean_(payload.Notes),
  });

  const created = findById_(FIXXIR.sheets.suppliers, "Supplier_ID", id);
  return normalizeSupplier_(created || {
    Supplier_ID: id,
    Supplier_Name: name,
  });
}

function getActiveSuppliers_() {
  return getRecords_(FIXXIR.sheets.suppliers)
    .filter((s) => !s.Status || s.Status === "Active")
    .map(normalizeSupplier_)
    .sort((a, b) => a.Supplier_Name.localeCompare(b.Supplier_Name));
}

function normalizeSupplier_(supplier) {
  supplier = supplier || {};
  return Object.assign({}, supplier, {
    Supplier_Name: getSupplierDisplayName_(supplier),
  });
}

function getSupplierDisplayName_(supplier) {
  supplier = supplier || {};
  return clean_(
    supplier.Supplier_Name ||
    supplier.Company_Name ||
    supplier.Name ||
    supplier.Full_Name ||
    supplier.Contact_Name ||
    supplier.Supplier_ID
  );
}

function saveSupplierCatalogItem(payload) {
  assertAuthorized_();
  ensureProcurementSchema_(getSpreadsheet_());
  payload = payload || {};

  const supplierId = clean_(payload.Supplier_ID);
  const itemName = clean_(payload.Supplier_Item_Name || payload.Item_Name);

  if (!supplierId) throw new Error("Vendor is required.");
  if (!itemName) throw new Error("Vendor item name is required.");

  if (!findById_(FIXXIR.sheets.suppliers, "Supplier_ID", supplierId)) {
    throw new Error("Vendor not found: " + supplierId);
  }

  const now = new Date();
  const catalogRows = getRecords_(FIXXIR.sheets.supplierCatalog);
  let supplierItemId = clean_(payload.Supplier_Item_ID);

  let existing = supplierItemId
    ? catalogRows.find((row) => row.Supplier_Item_ID === supplierItemId)
    : null;

  if (!existing) {
    const productId = clean_(payload.Product_ID);
    existing = catalogRows.find((row) =>
      row.Supplier_ID === supplierId &&
      (
        (productId && row.Product_ID === productId) ||
        (!productId &&
          clean_(row.Supplier_Item_Name).toLowerCase() === itemName.toLowerCase())
      ),
    );
  }

  const quotedPrice = numberOrBlank_(payload.Last_Quoted_Price);
  const quoteDate = quotedPrice === ""
    ? parseDate_(payload.Last_Quote_Date)
    : (parseDate_(payload.Last_Quote_Date) || now);

  const record = {
    Supplier_ID: supplierId,
    Product_ID: clean_(payload.Product_ID),
    Supplier_Item_Name: itemName,
    Brand: clean_(payload.Brand),
    Model: clean_(payload.Model),
    Variant: clean_(payload.Variant),
    Last_Quoted_Price: quotedPrice,
    Last_Quote_Date: quoteDate,
    Availability: clean_(payload.Availability) || "Unknown",
    Status: clean_(payload.Status) || "Active",
    Last_Updated: now,
    Notes: clean_(payload.Notes),
  };

  if (existing) {
    supplierItemId = existing.Supplier_Item_ID;
    updateRecordById_(
      FIXXIR.sheets.supplierCatalog,
      "Supplier_Item_ID",
      supplierItemId,
      record,
    );
  } else {
    supplierItemId = generateId_(FIXXIR.sheets.supplierCatalog);
    appendRecord_(FIXXIR.sheets.supplierCatalog, Object.assign({
      Supplier_Item_ID: supplierItemId,
      Created_At: now,
    }, record));
  }

  return getSupplierCatalogItem_(supplierItemId);
}

function getSupplierCatalogItem_(supplierItemId) {
  return findById_(
    FIXXIR.sheets.supplierCatalog,
    "Supplier_Item_ID",
    supplierItemId,
  );
}

function listSupplierCatalog(filters) {
  assertAuthorized_();
  ensureProcurementSchema_(getSpreadsheet_());
  filters = filters || {};

  const q = clean_(filters.q).toLowerCase();
  const supplierId = clean_(filters.supplierId);
  const suppliers = objectMap_(
    getActiveSuppliers_(),
    "Supplier_ID",
  );

  const purchases = objectMap_(
    getRecords_(FIXXIR.sheets.purchases),
    "Purchase_ID",
  );

  const historyByItem = {};
  getRecords_(FIXXIR.sheets.purchaseItems).forEach((item) => {
    const id = item.Supplier_Item_ID;
    if (!id || item.Unit_Cost === "" || item.Unit_Cost === null) return;

    const purchase = purchases[item.Purchase_ID] || {};
    if (!historyByItem[id]) historyByItem[id] = [];

    historyByItem[id].push({
      Purchase_ID: item.Purchase_ID,
      Purchase_Date: purchase.Purchase_Date || "",
      Unit_Cost: number_(item.Unit_Cost),
      Quantity: number_(item.Quantity),
    });
  });

  Object.values(historyByItem).forEach((history) =>
    history.sort((a, b) =>
      String(b.Purchase_Date || "").localeCompare(
        String(a.Purchase_Date || ""),
      ),
    ),
  );

  let rows = getRecords_(FIXXIR.sheets.supplierCatalog).map((row) => {
    const history = historyByItem[row.Supplier_Item_ID] || [];
    const latest = history[0] || null;
    const previous = history[1] || null;

    const latestPurchasePrice = latest
      ? latest.Unit_Cost
      : numberOrBlank_(row.Last_Purchase_Price);

    const previousPrice = previous ? previous.Unit_Cost : "";

    return Object.assign({}, row, {
      Supplier_Name: suppliers[row.Supplier_ID]
        ? suppliers[row.Supplier_ID].Supplier_Name
        : row.Supplier_ID,
      Latest_Purchase_Price_Calc: latestPurchasePrice,
      Previous_Purchase_Price_Calc: previousPrice,
      Price_Change_Calc:
        latestPurchasePrice !== "" && previousPrice !== ""
          ? number_(latestPurchasePrice) - number_(previousPrice)
          : "",
      Price_History_Count: history.length,
    });
  });

  if (supplierId) {
    rows = rows.filter((row) => row.Supplier_ID === supplierId);
  }

  if (q) {
    rows = rows.filter((row) =>
      [
        row.Supplier_Item_ID,
        row.Supplier_Name,
        row.Supplier_Item_Name,
        row.Product_ID,
        row.Brand,
        row.Model,
        row.Variant,
      ].some((value) =>
        String(value || "").toLowerCase().includes(q),
      ),
    );
  }

  rows.sort((a, b) =>
    String(a.Supplier_Item_Name || "").localeCompare(
      String(b.Supplier_Item_Name || ""),
    ),
  );

  return rows.slice(0, 300);
}

function getSupplierPriceHistory(supplierItemId) {
  assertAuthorized_();
  ensureProcurementSchema_(getSpreadsheet_());

  const id = clean_(supplierItemId);
  if (!id) throw new Error("Supplier item ID is required.");

  const catalogItem = getSupplierCatalogItem_(id);
  if (!catalogItem) throw new Error("Vendor catalog item not found: " + id);

  const purchaseMap = objectMap_(
    getRecords_(FIXXIR.sheets.purchases),
    "Purchase_ID",
  );

  const history = getRecords_(FIXXIR.sheets.purchaseItems)
    .filter(
      (item) =>
        item.Supplier_Item_ID === id &&
        item.Unit_Cost !== "" &&
        item.Unit_Cost !== null,
    )
    .map((item) => {
      const purchase = purchaseMap[item.Purchase_ID] || {};
      return {
        Purchase_ID: item.Purchase_ID,
        Purchase_Date: purchase.Purchase_Date || "",
        Unit_Cost: number_(item.Unit_Cost),
        Quantity: number_(item.Quantity),
      };
    })
    .sort((a, b) =>
      String(b.Purchase_Date || "").localeCompare(
        String(a.Purchase_Date || ""),
      ),
    );

  return {
    catalogItem,
    supplier: normalizeSupplier_(
      findById_(
        FIXXIR.sheets.suppliers,
        "Supplier_ID",
        catalogItem.Supplier_ID,
      ) || {},
    ),
    history,
  };
}

function listPurchases(filters) {
  assertAuthorized_();
  ensureProcurementSchema_(getSpreadsheet_());
  filters = filters || {};

  const q = clean_(filters.q).toLowerCase();
  const supplierId = clean_(filters.supplierId);
  const status = clean_(filters.status);

  const supplierMap = objectMap_(
    getActiveSuppliers_(),
    "Supplier_ID",
  );

  let rows = getRecords_(FIXXIR.sheets.purchases).map((purchase) =>
    Object.assign({}, purchase, {
      Supplier_Name: supplierMap[purchase.Supplier_ID]
        ? supplierMap[purchase.Supplier_ID].Supplier_Name
        : purchase.Supplier_ID,
    }),
  );

  if (supplierId) rows = rows.filter((p) => p.Supplier_ID === supplierId);
  if (status) rows = rows.filter((p) => p.Purchase_Status === status);

  if (q) {
    rows = rows.filter((p) =>
      [
        p.Purchase_ID,
        p.Supplier_Name,
        p.Supplier_Reference,
        p.Notes,
      ].some((value) =>
        String(value || "").toLowerCase().includes(q),
      ),
    );
  }

  rows.sort((a, b) => {
    const dateCmp = String(b.Purchase_Date || "").localeCompare(
      String(a.Purchase_Date || ""),
    );
    if (dateCmp) return dateCmp;
    return String(b.Created_At || "").localeCompare(
      String(a.Created_At || ""),
    );
  });

  return rows.slice(0, 300);
}

function getPurchase(purchaseId) {
  assertAuthorized_();
  ensureProcurementSchema_(getSpreadsheet_());

  const id = clean_(purchaseId);
  if (!id) throw new Error("Purchase ID is required.");

  const purchase = findById_(
    FIXXIR.sheets.purchases,
    "Purchase_ID",
    id,
  );
  if (!purchase) throw new Error("Purchase not found: " + id);

  const supplier = normalizeSupplier_(
    findById_(
      FIXXIR.sheets.suppliers,
      "Supplier_ID",
      purchase.Supplier_ID,
    ) || {},
  );

  const items = getRecords_(FIXXIR.sheets.purchaseItems)
    .filter((item) => item.Purchase_ID === id);

  const expenses = getRecords_(FIXXIR.sheets.purchaseExpenses)
    .filter((expense) => expense.Purchase_ID === id);

  return {
    purchase,
    supplier,
    items,
    expenses,
  };
}

function createPurchase(payload) {
  assertAuthorized_();
  ensureProcurementSchema_(getSpreadsheet_());
  payload = payload || {};

  requireFields_(payload, ["Supplier_ID", "Purchase_Date"]);

  const supplierId = clean_(payload.Supplier_ID);
  if (!findById_(FIXXIR.sheets.suppliers, "Supplier_ID", supplierId)) {
    throw new Error("Selected vendor no longer exists.");
  }

  let items = payload.Items || [];
  let expenses = payload.Expenses || [];

  if (typeof items === "string") items = JSON.parse(items || "[]");
  if (typeof expenses === "string") expenses = JSON.parse(expenses || "[]");

  if (!Array.isArray(items) || !items.length) {
    throw new Error("Add at least one purchased item.");
  }
  if (!Array.isArray(expenses)) expenses = [];

  const cleanItems = items.map((item, index) => {
    const name = clean_(item.Item_Name || item.Product_Name);
    const quantity = number_(item.Quantity);
    const rawCost = item.Unit_Cost;

    if (!name) {
      throw new Error(`Item ${index + 1}: item name is required.`);
    }
    if (!(quantity > 0)) {
      throw new Error(`Item ${index + 1}: quantity must be greater than zero.`);
    }

    const unitCost =
      rawCost === "" || rawCost === null || rawCost === undefined
        ? ""
        : number_(rawCost);

    if (unitCost !== "" && unitCost < 0) {
      throw new Error(`Item ${index + 1}: unit cost cannot be negative.`);
    }

    return {
      Supplier_Item_ID: clean_(item.Supplier_Item_ID),
      Product_ID: clean_(item.Product_ID),
      Item_Name: name,
      Quantity: quantity,
      Unit_Cost: unitCost,
      Base_Total: unitCost === "" ? "" : quantity * unitCost,
      IMEI_or_Serial: clean_(item.IMEI_or_Serial),
      Notes: clean_(item.Notes),
    };
  });

  const cleanExpenses = expenses
    .map((expense) => ({
      Expense_Type: clean_(expense.Expense_Type) || "Other",
      Description: clean_(expense.Description),
      Amount: number_(expense.Amount),
      Allocation_Method:
        clean_(expense.Allocation_Method) || "By Value",
      Payee: clean_(expense.Payee),
      Notes: clean_(expense.Notes),
    }))
    .filter((expense) => expense.Amount > 0);

  cleanExpenses.forEach((expense, index) => {
    if (!["By Value", "By Quantity"].includes(expense.Allocation_Method)) {
      throw new Error(
        `Expense ${index + 1}: allocation must be By Value or By Quantity.`,
      );
    }
  });

  const purchaseId = generateId_(FIXXIR.sheets.purchases);
  const purchaseDate = parseDate_(payload.Purchase_Date);
  if (!purchaseDate) throw new Error("Purchase date is required.");

  const now = new Date();

  appendRecord_(FIXXIR.sheets.purchases, {
    Purchase_ID: purchaseId,
    Purchase_Date: purchaseDate,
    Supplier_ID: supplierId,
    Supplier_Reference: clean_(payload.Supplier_Reference),
    Purchase_Status: clean_(payload.Purchase_Status) || "Received",
    Items_Subtotal: "",
    Additional_Costs: cleanExpenses.reduce(
      (sum, expense) => sum + expense.Amount,
      0,
    ),
    Landed_Total: "",
    Cost_Status: "Pending",
    Created_At: now,
    Created_By: currentUser_(),
    Last_Updated: now,
    Notes: clean_(payload.Notes),
  });

  cleanItems.forEach((item) => {
    let supplierItemId = item.Supplier_Item_ID;

    if (!supplierItemId) {
      supplierItemId = upsertSupplierCatalogFromPurchase_({
        Supplier_ID: supplierId,
        Product_ID: item.Product_ID,
        Supplier_Item_Name: item.Item_Name,
        Unit_Cost: item.Unit_Cost,
        Purchase_Date: purchaseDate,
      });
    } else if (item.Unit_Cost !== "") {
      updateSupplierCatalogPurchasePrice_(
        supplierItemId,
        item.Unit_Cost,
        purchaseDate,
      );
    }

    appendRecord_(FIXXIR.sheets.purchaseItems, {
      Purchase_Item_ID: generateId_(FIXXIR.sheets.purchaseItems),
      Purchase_ID: purchaseId,
      Supplier_ID: supplierId,
      Supplier_Item_ID: supplierItemId,
      Product_ID: item.Product_ID,
      Item_Name: item.Item_Name,
      Quantity: item.Quantity,
      Unit_Cost: item.Unit_Cost,
      Base_Total: item.Base_Total,
      Allocated_Expense: "",
      Landed_Total: "",
      Landed_Unit_Cost: "",
      Cost_Status: item.Unit_Cost === "" ? "Pending" : "Known",
      IMEI_or_Serial: item.IMEI_or_Serial,
      Notes: item.Notes,
    });
  });

  cleanExpenses.forEach((expense) => {
    appendRecord_(FIXXIR.sheets.purchaseExpenses, {
      Purchase_Expense_ID: generateId_(FIXXIR.sheets.purchaseExpenses),
      Purchase_ID: purchaseId,
      Purchase_Date: purchaseDate,
      Expense_Type: expense.Expense_Type,
      Description: expense.Description,
      Amount: expense.Amount,
      Allocation_Method: expense.Allocation_Method,
      Payee: expense.Payee,
      Created_At: now,
      Entered_By: currentUser_(),
      Notes: expense.Notes,
    });
  });

  recalculatePurchaseCosts_(purchaseId);
  return getPurchase(purchaseId);
}

function updatePurchaseItemCost(payload) {
  assertAuthorized_();
  payload = payload || {};

  const itemId = clean_(payload.Purchase_Item_ID);
  if (!itemId) throw new Error("Purchase item ID is required.");

  const item = findById_(
    FIXXIR.sheets.purchaseItems,
    "Purchase_Item_ID",
    itemId,
  );
  if (!item) throw new Error("Purchase item not found: " + itemId);

  const rawCost = payload.Unit_Cost;
  if (rawCost === "" || rawCost === null || rawCost === undefined) {
    throw new Error("Enter the actual unit cost.");
  }

  const unitCost = number_(rawCost);
  if (unitCost < 0) throw new Error("Unit cost cannot be negative.");

  updateRecordById_(
    FIXXIR.sheets.purchaseItems,
    "Purchase_Item_ID",
    itemId,
    {
      Unit_Cost: unitCost,
      Base_Total: unitCost * number_(item.Quantity),
      Cost_Status: "Known",
    },
  );

  const purchase = findById_(
    FIXXIR.sheets.purchases,
    "Purchase_ID",
    item.Purchase_ID,
  );

  if (item.Supplier_Item_ID && purchase) {
    updateSupplierCatalogPurchasePrice_(
      item.Supplier_Item_ID,
      unitCost,
      purchase.Purchase_Date,
    );
  }

  recalculatePurchaseCosts_(item.Purchase_ID);
  return getPurchase(item.Purchase_ID);
}

function recalculatePurchaseCosts_(purchaseId) {
  const items = getRecords_(FIXXIR.sheets.purchaseItems)
    .filter((item) => item.Purchase_ID === purchaseId);

  const expenses = getRecords_(FIXXIR.sheets.purchaseExpenses)
    .filter((expense) => expense.Purchase_ID === purchaseId);

  if (!items.length) return;

  const parsed = items.map((item) => {
    const known =
      item.Unit_Cost !== "" &&
      item.Unit_Cost !== null &&
      item.Unit_Cost !== undefined;

    const quantity = number_(item.Quantity);
    const unitCost = known ? number_(item.Unit_Cost) : "";
    const baseTotal = known ? quantity * unitCost : "";

    return {
      item,
      known,
      quantity,
      unitCost,
      baseTotal,
      allocated: 0,
      unresolvedAllocation: false,
    };
  });

  const allCostsKnown = parsed.every((row) => row.known);
  const subtotal = parsed.reduce(
    (sum, row) => sum + (row.known ? row.baseTotal : 0),
    0,
  );
  const totalQty = parsed.reduce(
    (sum, row) => sum + row.quantity,
    0,
  );

  expenses.forEach((expense) => {
    const amount = number_(expense.Amount);
    const method = clean_(expense.Allocation_Method) || "By Value";

    if (!(amount > 0)) return;

    if (method === "By Quantity") {
      parsed.forEach((row) => {
        row.allocated += totalQty > 0
          ? amount * (row.quantity / totalQty)
          : 0;
      });
      return;
    }

    if (!allCostsKnown || !(subtotal > 0)) {
      parsed.forEach((row) => {
        row.unresolvedAllocation = true;
      });
      return;
    }

    parsed.forEach((row) => {
      row.allocated += amount * (row.baseTotal / subtotal);
    });
  });

  let fullyKnown = true;

  parsed.forEach((row) => {
    const landedKnown = row.known && !row.unresolvedAllocation;
    if (!landedKnown) fullyKnown = false;

    const landedTotal = landedKnown
      ? row.baseTotal + row.allocated
      : "";

    const landedUnitCost =
      landedKnown && row.quantity > 0
        ? landedTotal / row.quantity
        : "";

    updateRecordById_(
      FIXXIR.sheets.purchaseItems,
      "Purchase_Item_ID",
      row.item.Purchase_Item_ID,
      {
        Base_Total: row.known ? row.baseTotal : "",
        Allocated_Expense:
          row.unresolvedAllocation ? "" : row.allocated,
        Landed_Total: landedTotal,
        Landed_Unit_Cost: landedUnitCost,
        Cost_Status: landedKnown ? "Known" : "Pending",
      },
    );
  });

  const additionalCosts = expenses.reduce(
    (sum, expense) => sum + number_(expense.Amount),
    0,
  );

  updateRecordById_(
    FIXXIR.sheets.purchases,
    "Purchase_ID",
    purchaseId,
    {
      Items_Subtotal: subtotal,
      Additional_Costs: additionalCosts,
      Landed_Total: fullyKnown ? subtotal + additionalCosts : "",
      Cost_Status: fullyKnown ? "Known" : "Pending",
      Last_Updated: new Date(),
    },
  );
}

function upsertSupplierCatalogFromPurchase_(payload) {
  const supplierId = clean_(payload.Supplier_ID);
  const productId = clean_(payload.Product_ID);
  const itemName = clean_(payload.Supplier_Item_Name);
  const unitCost = payload.Unit_Cost;
  const purchaseDate = payload.Purchase_Date;

  const rows = getRecords_(FIXXIR.sheets.supplierCatalog);
  let existing = rows.find((row) =>
    row.Supplier_ID === supplierId &&
    (
      (productId && row.Product_ID === productId) ||
      (!productId &&
        clean_(row.Supplier_Item_Name).toLowerCase() === itemName.toLowerCase())
    ),
  );

  if (existing) {
    if (unitCost !== "") {
      updateSupplierCatalogPurchasePrice_(
        existing.Supplier_Item_ID,
        unitCost,
        purchaseDate,
      );
    }
    return existing.Supplier_Item_ID;
  }

  const id = generateId_(FIXXIR.sheets.supplierCatalog);
  const now = new Date();

  appendRecord_(FIXXIR.sheets.supplierCatalog, {
    Supplier_Item_ID: id,
    Supplier_ID: supplierId,
    Product_ID: productId,
    Supplier_Item_Name: itemName,
    Last_Purchase_Price: unitCost,
    Last_Purchase_Date: unitCost === "" ? "" : purchaseDate,
    Availability: "Unknown",
    Status: "Active",
    Created_At: now,
    Last_Updated: now,
  });

  return id;
}

function updateSupplierCatalogPurchasePrice_(
  supplierItemId,
  unitCost,
  purchaseDate
) {
  if (!supplierItemId || unitCost === "") return;

  updateRecordById_(
    FIXXIR.sheets.supplierCatalog,
    "Supplier_Item_ID",
    supplierItemId,
    {
      Last_Purchase_Price: number_(unitCost),
      Last_Purchase_Date: parseDate_(purchaseDate),
      Last_Updated: new Date(),
    },
  );
}

/**
 * Run this after importing historical rows if you want to backfill the new
 * transaction-date columns again.
 *
 * Repair_Date is copied from Date_Received only when Repair_Date is blank.
 * Created_At is NEVER invented from Repair_Date.
 * Purchase_Date is copied only from a legacy Date / Transaction_Date column
 * when one exists.
 */
function migrateFixxirLegacyDates() {
  assertAuthorized_();
  const ss = getSpreadsheet_();

  const repairResult = ensureRepairDateSchema_(ss);
  const purchaseResult = migratePurchaseDates_(ss);

  return {
    ok: true,
    repairs: repairResult,
    purchases: purchaseResult,
  };
}

function ensureRepairDateSchema_(ss) {
  ss = ss || getSpreadsheet_();

  const sh = ensureSheetColumns_(
    ss,
    FIXXIR.sheets.repairs,
    ["Repair_Date", "Created_At"],
  );

  const lastRow = sh.getLastRow();
  if (lastRow < 2) {
    return { migratedRepairDates: 0, missingRepairDates: 0 };
  }

  const lastCol = sh.getLastColumn();
  const headers = sh
    .getRange(1, 1, 1, lastCol)
    .getValues()[0]
    .map(String);

  const repairDateIndex = headers.indexOf("Repair_Date");
  const createdAtIndex = headers.indexOf("Created_At");
  const dateReceivedIndex = headers.indexOf("Date_Received");
  const dateIndex = headers.indexOf("Date");
  const dateCreatedIndex = headers.indexOf("Date_Created");

  const rows = sh
    .getRange(2, 1, lastRow - 1, lastCol)
    .getValues();

  let migrated = 0;
  let missing = 0;
  let changed = false;

  rows.forEach((row) => {
    if (!row[repairDateIndex]) {
      const fallback =
        (dateReceivedIndex >= 0 && row[dateReceivedIndex]) ||
        (dateIndex >= 0 && row[dateIndex]) ||
        "";

      if (fallback) {
        row[repairDateIndex] = fallback;
        migrated += 1;
        changed = true;
      } else {
        missing += 1;
      }
    }

    // Only copy an actual legacy creation timestamp if such a column exists.
    // Do not pretend the transaction date is the creation timestamp.
    if (
      createdAtIndex >= 0 &&
      !row[createdAtIndex] &&
      dateCreatedIndex >= 0 &&
      row[dateCreatedIndex]
    ) {
      row[createdAtIndex] = row[dateCreatedIndex];
      changed = true;
    }
  });

  if (changed) {
    sh.getRange(2, 1, rows.length, lastCol).setValues(rows);
  }

  return {
    migratedRepairDates: migrated,
    missingRepairDates: missing,
  };
}

function migratePurchaseDates_(ss) {
  ss = ss || getSpreadsheet_();
  const sh = ss.getSheetByName(FIXXIR.sheets.purchases);

  if (!sh || sh.getLastRow() < 2) {
    return { migratedPurchaseDates: 0, missingPurchaseDates: 0 };
  }

  const lastCol = sh.getLastColumn();
  const headers = sh
    .getRange(1, 1, 1, lastCol)
    .getValues()[0]
    .map(String);

  const purchaseDateIndex = headers.indexOf("Purchase_Date");
  const dateIndex = headers.indexOf("Date");
  const transactionDateIndex = headers.indexOf("Transaction_Date");

  if (purchaseDateIndex < 0) {
    return { migratedPurchaseDates: 0, missingPurchaseDates: 0 };
  }

  const rows = sh
    .getRange(2, 1, sh.getLastRow() - 1, lastCol)
    .getValues();

  let migrated = 0;
  let missing = 0;
  let changed = false;

  rows.forEach((row) => {
    if (row[purchaseDateIndex]) return;

    const fallback =
      (transactionDateIndex >= 0 && row[transactionDateIndex]) ||
      (dateIndex >= 0 && row[dateIndex]) ||
      "";

    if (fallback) {
      row[purchaseDateIndex] = fallback;
      migrated += 1;
      changed = true;
    } else {
      missing += 1;
    }
  });

  if (changed) {
    sh.getRange(2, 1, rows.length, lastCol).setValues(rows);
  }

  return {
    migratedPurchaseDates: migrated,
    missingPurchaseDates: missing,
  };
}

function ensureProcurementSchema_(ss) {
  ss = ss || getSpreadsheet_();

  const supplierSheet = ss.getSheetByName(FIXXIR.sheets.suppliers)
    || ss.insertSheet(FIXXIR.sheets.suppliers);

  ensureSheetColumns_(
    ss,
    FIXXIR.sheets.suppliers,
    FIXXIR_SUPPLIER_REQUIRED_HEADERS,
  );

  // Populate canonical Supplier_Name from older name columns when possible.
  if (supplierSheet.getLastRow() >= 2) {
    const lastCol = supplierSheet.getLastColumn();
    const headers = supplierSheet
      .getRange(1, 1, 1, lastCol)
      .getValues()[0]
      .map(String);

    const supplierNameIndex = headers.indexOf("Supplier_Name");
    const sourceIndexes = [
      headers.indexOf("Company_Name"),
      headers.indexOf("Name"),
      headers.indexOf("Full_Name"),
      headers.indexOf("Contact_Name"),
    ].filter((i) => i >= 0);

    if (supplierNameIndex >= 0 && sourceIndexes.length) {
      const rows = supplierSheet
        .getRange(2, 1, supplierSheet.getLastRow() - 1, lastCol)
        .getValues();

      let changed = false;

      rows.forEach((row) => {
        if (row[supplierNameIndex]) return;

        const fallback = sourceIndexes
          .map((i) => row[i])
          .find((value) => value);

        if (fallback) {
          row[supplierNameIndex] = fallback;
          changed = true;
        }
      });

      if (changed) {
        supplierSheet
          .getRange(2, 1, rows.length, lastCol)
          .setValues(rows);
      }
    }
  }

  ensureSheetColumns_(
    ss,
    FIXXIR.sheets.supplierCatalog,
    FIXXIR_SUPPLIER_CATALOG_HEADERS,
  );

  ensureSheetColumns_(
    ss,
    FIXXIR.sheets.purchases,
    FIXXIR_PURCHASE_HEADERS,
  );

  ensureSheetColumns_(
    ss,
    FIXXIR.sheets.purchaseItems,
    FIXXIR_PURCHASE_ITEM_HEADERS,
  );

  ensureSheetColumns_(
    ss,
    FIXXIR.sheets.purchaseExpenses,
    FIXXIR_PURCHASE_EXPENSE_HEADERS,
  );

  migratePurchaseDates_(ss);
}

function repairDateKey_(repair) {
  return String(
    (repair && (
      repair.Repair_Date ||
      repair.Date_Received ||
      repair.Created_At
    )) || "",
  );
}

'''
    code = code.replace(backend_anchor, procurement_backend + backend_anchor, 1)

# ==========================================================
# Index.html — Repair Date field
# ==========================================================

# New Repair: insert actual repair date near Device_Type.
# This deliberately does NOT depend on one exact HTML formatting style, because
# earlier Fixxir patches may have reformatted the form.
if 'id="repairDate"' not in html:
    repair_date_html = (
        '\n          <div><label class="required">Repair date</label>'
        '<input class="input" type="date" name="Repair_Date" '
        'id="repairDate" required></div>'
    )

    device_match = re.search(
        r"""(?is)
        <div\b[^>]*>
        (?:(?!</div>).)*?
        <(?:select|input)\b
        (?=[^>]*(?:\bname=["']Device_Type["']|\bid=["']repairDeviceType["']))
        [^>]*>
        (?:(?!</div>).)*?
        </div>
        """,
        html,
        re.VERBOSE,
    )

    if device_match:
        pos = device_match.end()
        html = html[:pos] + repair_date_html + html[pos:]
    else:
        control_match = re.search(
            r"""(?is)<(?:select|input)\b
            (?=[^>]*(?:\bname=["']Device_Type["']|\bid=["']repairDeviceType["']))
            [^>]*>""",
            html,
            re.VERBOSE,
        )

        if not control_match:
            raise SystemExit(
                'ERROR: Could not locate the Device_Type control in New Repair. '
                'Search Index.html for name="Device_Type" or id="repairDeviceType".'
            )

        close_div = html.find("</div>", control_match.end())
        if close_div < 0:
            raise SystemExit(
                "ERROR: Found Device_Type, but could not find its closing </div>."
            )

        pos = close_div + len("</div>")
        html = html[:pos] + repair_date_html + html[pos:]

# Repair Edit: insert Repair Date near the Repair_Status control without
# depending on a specific one-line/multi-line layout.
if 'id="editRepairDate"' not in html:
    edit_repair_date_html = (
        '\n          <div><label class="required">Repair date</label>'
        '<input class="input" type="date" name="Repair_Date" '
        'id="editRepairDate" required></div>'
    )

    status_match = re.search(
        r"""(?is)
        <div\b[^>]*>
        (?:(?!</div>).)*?
        <select\b
        (?=[^>]*(?:\bname=["']Repair_Status["']|\bid=["']editRepairStatus["']))
        [^>]*>
        .*?
        </select>
        (?:(?!</div>).)*?
        </div>
        """,
        html,
        re.VERBOSE,
    )

    if status_match:
        pos = status_match.end()
        html = html[:pos] + edit_repair_date_html + html[pos:]
    else:
        control_match = re.search(
            r"""(?is)<select\b
            (?=[^>]*(?:\bname=["']Repair_Status["']|\bid=["']editRepairStatus["']))
            [^>]*>.*?</select>""",
            html,
            re.VERBOSE,
        )

        if not control_match:
            raise SystemExit(
                'ERROR: Could not locate the Repair_Status control in Edit Repair.'
            )

        close_div = html.find("</div>", control_match.end())
        if close_div < 0:
            raise SystemExit(
                "ERROR: Found Repair_Status, but could not find its closing </div>."
            )

        pos = close_div + len("</div>")
        html = html[:pos] + edit_repair_date_html + html[pos:]

# Open New Repair defaults to today's actual transaction date.
if "document.getElementById('repairDate').value" not in html:
    anchor = "    populateStaticSelects();\n    document.getElementById('repairModal').classList.add('open');"
    if anchor in html:
        html = html.replace(
            anchor,
            "    populateStaticSelects();\n"
            "    document.getElementById('repairDate').value=localToday_();\n"
            "    document.getElementById('repairModal').classList.add('open');",
            1,
        )

# Edit Repair populates historical Repair_Date.
if "editRepairDate').value" not in html:
    anchor = "    document.getElementById('editRepairStatus').value = r.Repair_Status || '';\n"
    if anchor in html:
        html = html.replace(
            anchor,
            anchor +
            "    document.getElementById('editRepairDate').value = dateOnly(r.Repair_Date || r.Date_Received);\n",
            1,
        )

# Display actual Repair Date, not creation-ish Date_Received label.
html = html.replace(
    "${detail('Received',dateOnly(r.Date_Received))}",
    "${detail('Repair date',dateOnly(r.Repair_Date||r.Date_Received))}",
)
html = html.replace(
    "${dateOnly(r.Date_Received)}",
    "${dateOnly(r.Repair_Date||r.Date_Received)}",
)

# ==========================================================
# Index.html — Purchases navigation
# ==========================================================

# Insert the Purchases button without depending on the exact existing buttons,
# labels, emojis, order, or whitespace in the sidebar.
if 'data-page="purchases"' not in html and "data-page='purchases'" not in html:
    nav_open = re.search(
        r'''(?is)<div\b[^>]*\bclass=["'][^"']*\bnav\b[^"']*["'][^>]*>''',
        html,
    )

    if not nav_open:
        raise SystemExit(
            'ERROR: Could not locate the sidebar <div class="nav"> block.'
        )

    nav_close = html.find("</div>", nav_open.end())
    if nav_close < 0:
        raise SystemExit(
            'ERROR: Found the sidebar navigation block but not its closing </div>.'
        )

    purchase_button = (
        '\n      <button data-page="purchases" '
        'onclick="navigate(\'purchases\',this)">▤ Purchases</button>'
    )

    html = html[:nav_close] + purchase_button + "\n    " + html[nav_close:]

# Add Purchases routing inside navigate(). We use several common existing
# routes as anchors, then fall back to the end of navigate().
if "if (page === 'purchases') renderPurchasesPage();" not in html:
    inserted_route = False

    route_candidates = [
        r'''(?m)^([ \t]*if\s*\(\s*page\s*===\s*['"]sales['"]\s*\)\s*renderSalesPage\(\);\s*)$''',
        r'''(?m)^([ \t]*if\s*\(\s*page\s*===\s*['"]finance['"]\s*\)\s*renderFinancePage\(\);\s*)$''',
        r'''(?m)^([ \t]*if\s*\(\s*page\s*===\s*['"]customers['"]\s*\)\s*renderCustomersPage\(\);\s*)$''',
    ]

    for pattern in route_candidates:
        match = re.search(pattern, html)
        if match:
            indent = re.match(r'[ \t]*', match.group(1)).group(0)
            insertion = (
                match.group(1)
                + "\n"
                + indent
                + "if (page === 'purchases') renderPurchasesPage();"
            )
            html = html[:match.start()] + insertion + html[match.end():]
            inserted_route = True
            break

    if not inserted_route:
        navigate_match = re.search(
            r'''(?is)function\s+navigate\s*\([^)]*\)\s*\{.*?\n[ \t]*\}''',
            html,
        )

        if not navigate_match:
            raise SystemExit(
                "ERROR: Could not locate navigate() to add the Purchases route."
            )

        block = navigate_match.group(0)
        close_pos = block.rfind("}")
        if close_pos < 0:
            raise SystemExit(
                "ERROR: Could not locate the end of navigate()."
            )

        block = (
            block[:close_pos]
            + "    if (page === 'purchases') renderPurchasesPage();\n"
            + block[close_pos:]
        )

        html = (
            html[:navigate_match.start()]
            + block
            + html[navigate_match.end():]
        )

# ==========================================================
# Purchase modals
# ==========================================================

if 'id="purchaseModal"' not in html:
    modal_anchor = '<div class="modal" id="financeModal">\n'
    if modal_anchor not in html:
        modal_anchor = '<div class="toast" id="toast"></div>\n'
    if modal_anchor not in html:
        raise SystemExit("ERROR: Could not find modal insertion point.")

    purchase_modals = r'''<div class="modal" id="purchaseModal">
  <div class="modal-box" style="width:min(1100px,100%)">
    <div class="modal-head"><h3>New Purchase</h3><button class="close" onclick="closeModal('purchaseModal')">×</button></div>
    <form id="purchaseForm" onsubmit="submitPurchase(event)">
      <div class="modal-body">
        <div class="section-head">
          <div><h3>Vendor & transaction</h3><div class="muted" style="font-size:12px;margin-top:4px">Purchase date is the actual date of the procurement transaction, not when the record was entered.</div></div>
          <button type="button" class="btn small" onclick="quickAddSupplier()">+ Add vendor</button>
        </div>

        <div class="form-grid">
          <div><label class="required">Vendor</label><select class="select" name="Supplier_ID" id="purchaseSupplier" required></select></div>
          <div><label class="required">Purchase date</label><input class="input" type="date" name="Purchase_Date" id="purchaseDate" required></div>
          <div><label>Vendor invoice / reference</label><input class="input" name="Supplier_Reference"></div>
          <div><label>Status</label><select class="select" name="Purchase_Status"><option>Received</option><option>Ordered</option><option>Part Received</option><option>Cancelled</option></select></div>
        </div>

        <div class="section-head" style="margin-top:24px">
          <div><h3>Purchased items</h3><div class="muted" style="font-size:12px;margin-top:4px">Items do not need to exist in the Fixxir catalog first. Buying an item automatically builds the vendor catalog.</div></div>
          <button type="button" class="btn small" onclick="addPurchaseItemRow()">+ Add item</button>
        </div>
        <div id="purchaseItems"></div>

        <div class="section-head" style="margin-top:24px">
          <div><h3>Shared purchase costs</h3><div class="muted" style="font-size:12px;margin-top:4px">Use this for express logistics, clearing, delivery, handling and other costs belonging to the whole purchase.</div></div>
          <button type="button" class="btn small" onclick="addPurchaseExpenseRow()">+ Add cost</button>
        </div>
        <div id="purchaseExpenses"><div class="empty" style="padding:14px">No shared costs added.</div></div>

        <div class="form-grid" style="margin-top:18px">
          <div class="full"><label>Notes</label><textarea class="textarea" name="Notes"></textarea></div>
        </div>
      </div>
      <div class="modal-foot"><button type="button" class="btn" onclick="closeModal('purchaseModal')">Cancel</button><button class="btn primary" type="submit">Create purchase</button></div>
    </form>
  </div>
</div>

<div class="modal" id="purchaseDetailModal">
  <div class="modal-box" style="width:min(1100px,100%)">
    <div class="modal-head"><h3 id="purchaseDetailTitle">Purchase</h3><button class="close" onclick="closeModal('purchaseDetailModal')">×</button></div>
    <div class="modal-body" id="purchaseDetailBody"></div>
  </div>
</div>

<div class="modal" id="vendorCatalogModal">
  <div class="modal-box" style="width:min(720px,100%)">
    <div class="modal-head"><h3>Vendor Catalog Price</h3><button class="close" onclick="closeModal('vendorCatalogModal')">×</button></div>
    <form id="vendorCatalogForm" onsubmit="submitVendorCatalogItem(event)">
      <div class="modal-body">
        <input type="hidden" name="Supplier_Item_ID" id="vendorCatalogItemId">
        <div class="form-grid">
          <div><label class="required">Vendor</label><select class="select" name="Supplier_ID" id="vendorCatalogSupplier" required></select></div>
          <div><label>Availability</label><select class="select" name="Availability"><option>Unknown</option><option>Available</option><option>Limited</option><option>Out of stock</option><option>On request</option></select></div>
          <div class="full"><label class="required">Vendor item</label><input class="input" name="Supplier_Item_Name" required placeholder="e.g. iPhone 16 Pro 256GB"></div>
          <div><label>Latest quoted price (₦)</label><input class="input" type="number" min="0" step="1" name="Last_Quoted_Price"></div>
          <div><label>Quote date</label><input class="input" type="date" name="Last_Quote_Date" id="vendorQuoteDate"></div>
          <div><label>Brand</label><input class="input" name="Brand"></div>
          <div><label>Model</label><input class="input" name="Model"></div>
          <div class="full"><label>Variant / specification</label><input class="input" name="Variant" placeholder="Color, storage, RAM, region, etc."></div>
          <div class="full"><label>Notes</label><textarea class="textarea" name="Notes"></textarea></div>
        </div>
      </div>
      <div class="modal-foot"><button type="button" class="btn" onclick="closeModal('vendorCatalogModal')">Cancel</button><button class="btn primary" type="submit">Save vendor price</button></div>
    </form>
  </div>
</div>

'''
    html = html.replace(modal_anchor, purchase_modals + modal_anchor, 1)

# ==========================================================
# Globals + supplier select population
# ==========================================================

if "let PURCHASE_ITEM_SEQ" not in html:
    globals_anchor = "  let SALE_ITEM_SEQ = 0;\n"
    if globals_anchor in html:
        html = html.replace(
            globals_anchor,
            globals_anchor +
            "  let PURCHASE_ITEM_SEQ = 0;\n"
            "  let PURCHASE_EXPENSE_SEQ = 0;\n"
            "  let PURCHASE_TIMER = null;\n"
            "  let CURRENT_PURCHASE = null;\n",
            1,
        )
    else:
        script_anchor = "<script>\n"
        html = html.replace(
            script_anchor,
            script_anchor +
            "  let PURCHASE_ITEM_SEQ = 0;\n"
            "  let PURCHASE_EXPENSE_SEQ = 0;\n"
            "  let PURCHASE_TIMER = null;\n"
            "  let CURRENT_PURCHASE = null;\n",
            1,
        )

if "fillSupplierSelects();" not in html:
    populate_end_candidates = [
        "    fillSelect('salePaymentMethodDetail', BOOT.settings.Payment_Method || [], 'Select method');\n",
        "    fillSelect('financeCategory', BOOT.settings.Finance_Category || [], 'Select category');\n",
    ]
    for anchor in populate_end_candidates:
        if anchor in html:
            html = html.replace(anchor, anchor + "    fillSupplierSelects();\n", 1)
            break

# ==========================================================
# Purchases page/client logic
# ==========================================================

if "function renderPurchasesPage()" not in html:
    ui_anchor = "  function renderFinancePage() {\n"
    if ui_anchor not in html:
        ui_anchor = "  function openNewRepair(){\n"
    if ui_anchor not in html:
        raise SystemExit("ERROR: Could not find UI insertion anchor.")

    purchase_ui = r'''  /* FIXXIR_PROCUREMENT_UI_V1 */

  function localToday_(){
    const now=new Date();
    const local=new Date(now.getTime()-now.getTimezoneOffset()*60000);
    return local.toISOString().slice(0,10);
  }

  function fillSupplierSelects(){
    const values=(BOOT?.suppliers||[]).map(s=>({
      value:s.Supplier_ID,
      label:s.Supplier_Name||s.Supplier_ID
    }));
    fillSelect('purchaseSupplier',values,'Select vendor');
    fillSelect('vendorCatalogSupplier',values,'Select vendor');
    fillSelect('purchaseSupplierFilter',values,'All vendors');
    fillSelect('catalogSupplierFilter',values,'All vendors');
  }

  async function refreshSuppliers(){
    try{
      const data=await server('getProcurementPageData',{});
      BOOT.suppliers=data.suppliers||[];
      fillSupplierSelects();
    }catch(e){toast(e.message,true)}
  }

  async function quickAddSupplier(){
    const name=window.prompt('Vendor name');
    if(!name||!name.trim())return;

    const phone=window.prompt('Vendor phone (optional)')||'';
    showLoading(true);
    try{
      const supplier=await server('createSupplier',{Supplier_Name:name.trim(),Phone:phone.trim()});
      await refreshSuppliers();
      const select=document.getElementById('purchaseSupplier');
      if(select)select.value=supplier.Supplier_ID;
      toast(`Vendor ready: ${supplier.Supplier_Name}`);
    }catch(e){
      toast(e.message,true);
    }finally{
      showLoading(false);
    }
  }

  async function renderPurchasesPage(){
    document.getElementById('content').innerHTML=`
      <div class="toolbar">
        <div><h2>Purchases</h2><div class="muted" style="margin-top:5px">Vendor catalog, actual purchase prices, shared procurement costs and landed cost.</div></div>
        <div class="actions">
          <button class="btn" onclick="openVendorCatalogModal()">+ Vendor Price</button>
          <button class="btn primary" onclick="openNewPurchase()">+ New Purchase</button>
        </div>
      </div>

      <div class="grid kpis" id="purchaseKpis">
        ${kpi('Purchases','—','Procurement transactions')}
        ${kpi('Known landed value','—','Purchases whose costs are complete')}
        ${kpi('Shared costs','—','Logistics, clearing and related costs')}
        ${kpi('Pending costs','—','Purchases still missing cost information')}
      </div>

      <div class="card section" style="margin-bottom:18px">
        <div class="section-head"><h3>Purchase history</h3></div>
        <div class="filters" style="margin-bottom:14px">
          <input class="input" id="purchaseQ" placeholder="Search purchase, vendor or reference…" oninput="debouncedPurchaseLoad()">
          <select class="select" id="purchaseSupplierFilter" onchange="loadPurchases()"></select>
          <select class="select" id="purchaseStatusFilter" onchange="loadPurchases()">
            <option value="">All statuses</option>
            <option>Received</option><option>Ordered</option><option>Part Received</option><option>Cancelled</option>
          </select>
        </div>
        <div id="purchaseList"><div class="empty">Loading purchases…</div></div>
      </div>

      <div class="card section">
        <div class="section-head">
          <div><h3>Vendor catalog & price comparison</h3><div class="muted" style="font-size:12px;margin-top:4px">Search an item to see which vendors have supplied or quoted it and how prices changed.</div></div>
          <button class="btn small" onclick="openVendorCatalogModal()">+ Add vendor price</button>
        </div>
        <div class="filters" style="margin-bottom:14px">
          <input class="input" id="catalogQ" placeholder="Search iPhone 16, charger, screen…" oninput="debouncedPurchaseLoad()">
          <select class="select" id="catalogSupplierFilter" onchange="loadPurchases()"></select>
        </div>
        <div id="vendorCatalogList"><div class="empty">Search or add vendor items.</div></div>
      </div>`;

    fillSupplierSelects();
    await loadPurchases();
  }

  function debouncedPurchaseLoad(){
    clearTimeout(PURCHASE_TIMER);
    PURCHASE_TIMER=setTimeout(loadPurchases,300);
  }

  async function loadPurchases(){
    try{
      const data=await server('getProcurementPageData',{
        q:document.getElementById('purchaseQ')?.value||'',
        supplierId:document.getElementById('purchaseSupplierFilter')?.value||'',
        status:document.getElementById('purchaseStatusFilter')?.value||'',
        catalogQ:document.getElementById('catalogQ')?.value||''
      });

      BOOT.suppliers=data.suppliers||BOOT.suppliers||[];

      const s=data.summary||{};
      const kpis=document.getElementById('purchaseKpis');
      if(kpis){
        kpis.innerHTML=`
          ${kpi('Purchases',s.purchases||0,'Procurement transactions')}
          ${kpi('Known landed value',money(s.knownPurchaseValue),'Complete landed-cost purchases')}
          ${kpi('Shared costs',money(s.additionalCosts),'Logistics, clearing and related costs')}
          ${kpi('Pending costs',s.pendingCosts||0,'Missing item/allocation cost information')}`;
      }

      renderPurchaseRows(data.purchases||[]);
      renderVendorCatalogRows(data.catalog||[]);
    }catch(e){
      toast(e.message,true);
    }
  }

  function renderPurchaseRows(rows){
    const box=document.getElementById('purchaseList');
    if(!box)return;

    if(!rows.length){
      box.innerHTML='<div class="empty">No purchases found.</div>';
      return;
    }

    box.innerHTML=`<div class="table-wrap"><table>
      <thead><tr><th>Purchase</th><th>Purchase date</th><th>Vendor</th><th>Status</th><th>Items</th><th>Shared costs</th><th>Landed total</th><th>Cost status</th></tr></thead>
      <tbody>${rows.map(p=>`<tr class="clickable" onclick="openPurchase('${escAttr(p.Purchase_ID)}')">
        <td><b>${esc(p.Purchase_ID)}</b><br><span class="muted">${esc(p.Supplier_Reference||'')}</span></td>
        <td>${dateOnly(p.Purchase_Date)||'—'}</td>
        <td>${esc(p.Supplier_Name||p.Supplier_ID||'')}</td>
        <td>${statusBadge(p.Purchase_Status||'')}</td>
        <td class="money">${p.Items_Subtotal===''?'Pending':money(p.Items_Subtotal)}</td>
        <td class="money">${money(p.Additional_Costs)}</td>
        <td class="money">${p.Landed_Total===''?'Pending':money(p.Landed_Total)}</td>
        <td>${p.Cost_Status==='Known'?'<span class="status ready">Known</span>':'<span class="status">Pending</span>'}</td>
      </tr>`).join('')}</tbody>
    </table></div>`;
  }

  function renderVendorCatalogRows(rows){
    const box=document.getElementById('vendorCatalogList');
    if(!box)return;

    if(!rows.length){
      box.innerHTML='<div class="empty">No vendor catalog items found.</div>';
      return;
    }

    box.innerHTML=`<div class="table-wrap"><table>
      <thead><tr><th>Item</th><th>Vendor</th><th>Latest quote</th><th>Last purchase</th><th>Change</th><th>Availability</th><th>History</th></tr></thead>
      <tbody>${rows.map(row=>{
        const latest=row.Latest_Purchase_Price_Calc;
        const change=row.Price_Change_Calc;
        const changeText=change===''?'—':`${num(change)>0?'+':''}${money(change)}`;
        return `<tr>
          <td><b>${esc(row.Supplier_Item_Name)}</b><br><span class="muted">${esc([row.Brand,row.Model,row.Variant].filter(Boolean).join(' · '))}</span></td>
          <td>${esc(row.Supplier_Name||row.Supplier_ID||'')}</td>
          <td>${row.Last_Quoted_Price===''?'—':money(row.Last_Quoted_Price)}<br><span class="muted">${dateOnly(row.Last_Quote_Date)||''}</span></td>
          <td>${latest===''?'—':money(latest)}<br><span class="muted">${dateOnly(row.Last_Purchase_Date)||''}</span></td>
          <td class="money">${changeText}</td>
          <td>${esc(row.Availability||'Unknown')}</td>
          <td><button class="btn small" onclick="showVendorPriceHistory('${escAttr(row.Supplier_Item_ID)}')">${esc(row.Price_History_Count||0)} purchase(s)</button></td>
        </tr>`;
      }).join('')}</tbody>
    </table></div>`;
  }

  function openNewPurchase(){
    document.getElementById('purchaseForm').reset();
    document.getElementById('purchaseItems').innerHTML='';
    document.getElementById('purchaseExpenses').innerHTML='<div class="empty" style="padding:14px">No shared costs added.</div>';

    PURCHASE_ITEM_SEQ=0;
    PURCHASE_EXPENSE_SEQ=0;

    fillSupplierSelects();
    document.getElementById('purchaseDate').value=localToday_();
    addPurchaseItemRow();
    document.getElementById('purchaseModal').classList.add('open');
  }

  function addPurchaseItemRow(item={}){
    PURCHASE_ITEM_SEQ+=1;
    const row=document.createElement('div');
    row.className='card section purchase-item-row';
    row.style.marginBottom='10px';

    row.innerHTML=`
      <div class="section-head">
        <h3>Item ${PURCHASE_ITEM_SEQ}</h3>
        <button type="button" class="btn small" onclick="removePurchaseItemRow(this)">Remove</button>
      </div>
      <div class="form-grid">
        <div class="full"><label class="required">Item</label><input class="input" data-field="Item_Name" value="${escAttr(item.Item_Name||'')}" placeholder="e.g. iPhone 16 Pro 256GB, Bespoke Charger"></div>
        <div><label class="required">Quantity</label><input class="input" type="number" min="1" step="1" data-field="Quantity" value="${escAttr(item.Quantity||1)}"></div>
        <div><label>Actual unit cost (₦)</label><input class="input" type="number" min="0" step="1" data-field="Unit_Cost" value="${escAttr(item.Unit_Cost??'')}" placeholder="Can be filled later"></div>
        <div><label>IMEI / Serial</label><input class="input" data-field="IMEI_or_Serial" value="${escAttr(item.IMEI_or_Serial||'')}" placeholder="Optional"></div>
        <div class="full"><label>Notes</label><input class="input" data-field="Notes" value="${escAttr(item.Notes||'')}"></div>
      </div>`;

    document.getElementById('purchaseItems').appendChild(row);
  }

  function removePurchaseItemRow(button){
    const rows=document.querySelectorAll('.purchase-item-row');
    if(rows.length<=1){
      toast('A purchase needs at least one item.',true);
      return;
    }
    button.closest('.purchase-item-row').remove();
  }

  function addPurchaseExpenseRow(expense={}){
    const box=document.getElementById('purchaseExpenses');
    if(box.querySelector('.empty'))box.innerHTML='';

    PURCHASE_EXPENSE_SEQ+=1;
    const row=document.createElement('div');
    row.className='card section purchase-expense-row';
    row.style.marginBottom='10px';

    row.innerHTML=`
      <div class="section-head">
        <h3>Shared cost ${PURCHASE_EXPENSE_SEQ}</h3>
        <button type="button" class="btn small" onclick="removePurchaseExpenseRow(this)">Remove</button>
      </div>
      <div class="form-grid">
        <div><label>Type</label><select class="select" data-field="Expense_Type"><option>Logistics</option><option>Express Logistics</option><option>Clearing</option><option>Handling</option><option>Delivery</option><option>Packaging</option><option>Other</option></select></div>
        <div><label class="required">Amount (₦)</label><input class="input" type="number" min="1" step="1" data-field="Amount" value="${escAttr(expense.Amount||'')}"></div>
        <div><label>Allocate</label><select class="select" data-field="Allocation_Method"><option>By Value</option><option>By Quantity</option></select></div>
        <div><label>Payee</label><input class="input" data-field="Payee" value="${escAttr(expense.Payee||'')}"></div>
        <div class="full"><label>Description</label><input class="input" data-field="Description" value="${escAttr(expense.Description||'')}"></div>
      </div>`;

    box.appendChild(row);
  }

  function removePurchaseExpenseRow(button){
    button.closest('.purchase-expense-row').remove();
    const box=document.getElementById('purchaseExpenses');
    if(!box.querySelector('.purchase-expense-row')){
      box.innerHTML='<div class="empty" style="padding:14px">No shared costs added.</div>';
    }
  }

  function purchaseItemsPayload(){
    return [...document.querySelectorAll('.purchase-item-row')].map(row=>{
      const get=field=>row.querySelector(`[data-field="${field}"]`)?.value||'';
      return {
        Item_Name:get('Item_Name'),
        Quantity:get('Quantity'),
        Unit_Cost:get('Unit_Cost'),
        IMEI_or_Serial:get('IMEI_or_Serial'),
        Notes:get('Notes')
      };
    });
  }

  function purchaseExpensesPayload(){
    return [...document.querySelectorAll('.purchase-expense-row')].map(row=>{
      const get=field=>row.querySelector(`[data-field="${field}"]`)?.value||'';
      return {
        Expense_Type:get('Expense_Type'),
        Amount:get('Amount'),
        Allocation_Method:get('Allocation_Method'),
        Payee:get('Payee'),
        Description:get('Description')
      };
    });
  }

  async function submitPurchase(e){
    e.preventDefault();
    const data=formObject(e.target);
    data.Items=purchaseItemsPayload();
    data.Expenses=purchaseExpensesPayload();

    showLoading(true);
    try{
      CURRENT_PURCHASE=await server('createPurchase',data);
      closeModal('purchaseModal');
      toast(`Created ${CURRENT_PURCHASE.purchase.Purchase_ID}`);
      if(CURRENT_PAGE==='purchases')await loadPurchases();
      renderPurchaseDetail(CURRENT_PURCHASE);
      document.getElementById('purchaseDetailModal').classList.add('open');
    }catch(err){
      toast(err.message,true);
    }finally{
      showLoading(false);
    }
  }

  async function openPurchase(id){
    showLoading(true);
    try{
      CURRENT_PURCHASE=await server('getPurchase',id);
      renderPurchaseDetail(CURRENT_PURCHASE);
      document.getElementById('purchaseDetailModal').classList.add('open');
    }catch(e){
      toast(e.message,true);
    }finally{
      showLoading(false);
    }
  }

  function renderPurchaseDetail(data){
    const p=data.purchase||{};
    const s=data.supplier||{};
    const items=data.items||[];
    const expenses=data.expenses||[];

    document.getElementById('purchaseDetailTitle').textContent=
      `${p.Purchase_ID||'Purchase'} · ${s.Supplier_Name||p.Supplier_ID||''}`;

    document.getElementById('purchaseDetailBody').innerHTML=`
      <div class="repair-hero">
        <div>
          <div class="detail-list">
            ${detail('Vendor',esc(s.Supplier_Name||p.Supplier_ID||'—'))}
            ${detail('Purchase date',dateOnly(p.Purchase_Date)||'—')}
            ${detail('Status',statusBadge(p.Purchase_Status||''))}
            ${detail('Vendor reference',esc(p.Supplier_Reference||'—'))}
            ${detail('Created at',p.Created_At?dateOnly(p.Created_At):'—')}
            ${detail('Cost status',p.Cost_Status==='Known'?'<span class="status ready">Known</span>':'<span class="status">Pending</span>')}
          </div>
        </div>
        <div class="finance-box">
          <div class="kpi-label" style="color:#bfd0df">Landed cost</div>
          <div class="finance-row"><span>Items</span><b>${money(p.Items_Subtotal)}</b></div>
          <div class="finance-row"><span>Shared costs</span><b>${money(p.Additional_Costs)}</b></div>
          <div class="finance-row big"><span>Landed total</span><span>${p.Landed_Total===''?'Pending':money(p.Landed_Total)}</span></div>
        </div>
      </div>

      <div style="margin-top:24px" class="section-head"><h3>Purchased items</h3></div>
      ${purchaseItemsTable(items)}

      <div style="margin-top:24px" class="section-head"><h3>Shared costs</h3></div>
      ${purchaseExpensesTable(expenses)}
    `;
  }

  function purchaseItemsTable(rows){
    if(!rows.length)return '<div class="empty">No purchase items.</div>';

    return `<div class="table-wrap"><table>
      <thead><tr><th>Item</th><th>Qty</th><th>Unit cost</th><th>Allocated cost</th><th>Landed/unit</th><th>IMEI / Serial</th><th></th></tr></thead>
      <tbody>${rows.map(item=>`<tr>
        <td><b>${esc(item.Item_Name)}</b></td>
        <td>${esc(item.Quantity)}</td>
        <td class="money">${item.Unit_Cost===''?'Pending':money(item.Unit_Cost)}</td>
        <td class="money">${item.Allocated_Expense===''?'Pending':money(item.Allocated_Expense)}</td>
        <td class="money">${item.Landed_Unit_Cost===''?'Pending':money(item.Landed_Unit_Cost)}</td>
        <td>${esc(item.IMEI_or_Serial||'')}</td>
        <td>${item.Unit_Cost===''?`<button class="btn small" onclick="setPurchaseItemCost('${escAttr(item.Purchase_Item_ID)}')">Set cost</button>`:''}</td>
      </tr>`).join('')}</tbody>
    </table></div>`;
  }

  function purchaseExpensesTable(rows){
    if(!rows.length)return '<div class="empty">No shared purchase costs.</div>';

    return `<div class="table-wrap"><table>
      <thead><tr><th>Type</th><th>Description</th><th>Amount</th><th>Allocation</th><th>Payee</th></tr></thead>
      <tbody>${rows.map(x=>`<tr>
        <td>${esc(x.Expense_Type)}</td>
        <td>${esc(x.Description||'')}</td>
        <td class="money">${money(x.Amount)}</td>
        <td>${esc(x.Allocation_Method||'By Value')}</td>
        <td>${esc(x.Payee||'')}</td>
      </tr>`).join('')}</tbody>
    </table></div>`;
  }

  async function setPurchaseItemCost(itemId){
    const item=(CURRENT_PURCHASE?.items||[]).find(x=>x.Purchase_Item_ID===itemId);
    if(!item)return;

    const input=window.prompt(`Actual unit cost for ${item.Item_Name}`,item.Unit_Cost||'');
    if(input===null||String(input).trim()==='')return;

    showLoading(true);
    try{
      CURRENT_PURCHASE=await server('updatePurchaseItemCost',{
        Purchase_Item_ID:itemId,
        Unit_Cost:input
      });
      renderPurchaseDetail(CURRENT_PURCHASE);
      if(CURRENT_PAGE==='purchases')await loadPurchases();
      toast('Purchase cost updated');
    }catch(e){
      toast(e.message,true);
    }finally{
      showLoading(false);
    }
  }

  function openVendorCatalogModal(){
    document.getElementById('vendorCatalogForm').reset();
    document.getElementById('vendorCatalogItemId').value='';
    fillSupplierSelects();
    document.getElementById('vendorQuoteDate').value=localToday_();
    document.getElementById('vendorCatalogModal').classList.add('open');
  }

  async function submitVendorCatalogItem(e){
    e.preventDefault();
    const data=formObject(e.target);

    showLoading(true);
    try{
      await server('saveSupplierCatalogItem',data);
      closeModal('vendorCatalogModal');
      toast('Vendor catalog updated');
      if(CURRENT_PAGE==='purchases')await loadPurchases();
    }catch(err){
      toast(err.message,true);
    }finally{
      showLoading(false);
    }
  }

  async function showVendorPriceHistory(supplierItemId){
    showLoading(true);
    try{
      const data=await server('getSupplierPriceHistory',supplierItemId);
      const item=data.catalogItem||{};
      const supplier=data.supplier||{};
      const history=data.history||[];

      document.getElementById('purchaseDetailTitle').textContent=
        `${item.Supplier_Item_Name||'Vendor item'} · ${supplier.Supplier_Name||''}`;

      document.getElementById('purchaseDetailBody').innerHTML=`
        <div class="detail-list">
          ${detail('Vendor',esc(supplier.Supplier_Name||'—'))}
          ${detail('Latest quoted price',item.Last_Quoted_Price===''?'—':money(item.Last_Quoted_Price))}
          ${detail('Last quote date',dateOnly(item.Last_Quote_Date)||'—')}
          ${detail('Availability',esc(item.Availability||'Unknown'))}
        </div>
        <div style="margin-top:24px" class="section-head"><h3>Actual purchase price history</h3></div>
        ${history.length?`<div class="table-wrap"><table>
          <thead><tr><th>Purchase date</th><th>Purchase</th><th>Qty</th><th>Unit cost</th></tr></thead>
          <tbody>${history.map(h=>`<tr>
            <td>${dateOnly(h.Purchase_Date)||'—'}</td>
            <td>${esc(h.Purchase_ID)}</td>
            <td>${esc(h.Quantity)}</td>
            <td class="money">${money(h.Unit_Cost)}</td>
          </tr>`).join('')}</tbody>
        </table></div>`:'<div class="empty">No actual purchases recorded for this vendor item yet.</div>'}`;

      document.getElementById('purchaseDetailModal').classList.add('open');
    }catch(e){
      toast(e.message,true);
    }finally{
      showLoading(false);
    }
  }

'''
    html = html.replace(ui_anchor, purchase_ui + ui_anchor, 1)

# ==========================================================
# Final validation
# ==========================================================

required_code = [
    'supplierCatalog: "Supplier_Catalog"',
    'Purchases: "PUR"',
    'const FIXXIR_PURCHASE_HEADERS',
    'function createPurchase(payload)',
    'function listSupplierCatalog(filters)',
    'function migrateFixxirLegacyDates()',
    'function ensureRepairDateSchema_(ss)',
    'Repair_Date: repairDate',
]

required_html = [
    'function renderPurchasesPage()',
    'id="purchaseModal"',
    'id="repairDate"',
    'id="editRepairDate"',
    'function submitPurchase(e)',
    'function showVendorPriceHistory',
]

missing = [x for x in required_code if x not in code] + [x for x in required_html if x not in html]
if missing:
    raise SystemExit("ERROR: Patch validation failed. Missing: " + ", ".join(missing))

code_path.write_text(code, encoding="utf-8")
html_path.write_text(html, encoding="utf-8")
PY

echo
echo "======================================================"
echo " Fixxir Procurement + Date patch applied"
echo "======================================================"
echo
echo "Changed:"
echo "  $CODE_FILE"
echo "  $INDEX_FILE"
echo
echo "Backups:"
echo "  ${CODE_FILE}.before-procurement-v1.bak"
echo "  ${INDEX_FILE}.before-procurement-v1.bak"
echo
echo "Review before deploying:"
echo "  git diff --check"
echo "  git diff -- $CODE_FILE $INDEX_FILE"
echo
echo "Then deploy:"
echo "  npm run deploy"
echo
echo "After deployment:"
echo "  - Opening the app/initialization creates the procurement sheets."
echo "  - Existing repairs get Repair_Date from Date_Received when available."
echo "  - New repairs require an explicit Repair Date."
echo "  - New purchases require an explicit Purchase Date."
echo "  - Created_At is stored separately and is not used as the transaction date."
echo
echo "If you import older repair/purchase rows later, run from Apps Script:"
echo "  migrateFixxirLegacyDates()"
