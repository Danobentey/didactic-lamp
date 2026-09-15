#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# Fixxir Sales Phase 2 — Flexible catalog + quotes
# ==========================================================
# Requires Sales Phase 1.
#
# Adds:
# - Ad-hoc products remain first-class; no catalog/inventory prerequisite.
# - Optional Product_Catalog built organically from sales/quotes.
# - Unknown/estimated costs stay unknown instead of becoming ₦0.
# - Profit is shown as pending until actual costs are known.
# - Sale item cost can be filled in later.
# - Quote workflow (QUO IDs), including price-pending quotes.
# - Convert a fully-priced quote into a pending-fulfilment sale.
# - Optional catalog linkage on sale/quote lines.
#
# Inventory linkage fields are added now, but stock deduction is NOT done yet.
# That comes with the Purchase/Inventory phase.
# ==========================================================

CODE_FILE="${1:-Code.js}"
INDEX_FILE="${2:-Index.html}"

for f in "$CODE_FILE" "$INDEX_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: $f not found."
    echo "Run this script from the Fixxir repository root."
    exit 1
  fi
done

if ! grep -q 'function createSale(payload)' "$CODE_FILE" || \
   ! grep -q 'function renderSalesPage()' "$INDEX_FILE"; then
  echo "ERROR: Sales Phase 1 is not present."
  echo "Apply/deploy patch-sales-phase1.sh first."
  exit 1
fi

if grep -q 'function saveQuote(payload)' "$CODE_FILE" && \
   grep -q 'function openNewQuote()' "$INDEX_FILE"; then
  echo "Sales Phase 2 is already installed."
  exit 0
fi

cp "$CODE_FILE" "${CODE_FILE}.before-flexible-sales-phase2.bak"
cp "$INDEX_FILE" "${INDEX_FILE}.before-flexible-sales-phase2.bak"

python3 - "$CODE_FILE" "$INDEX_FILE" <<'PY'
from pathlib import Path
import sys

code_path = Path(sys.argv[1])
html_path = Path(sys.argv[2])

code = code_path.read_text(encoding="utf-8")
html = html_path.read_text(encoding="utf-8")


def must_replace(text, old, new, label):
    if old not in text:
        raise SystemExit(
            f"ERROR: Could not find expected anchor for {label}. "
            "Your files may differ from the current Fixxir version. "
            "Backups were created; no modified files have been written."
        )
    return text.replace(old, new, 1)


# ==========================================================
# 1. Register Product Catalog + Quote sheets and prefixes
# ==========================================================

if 'catalog: "Product_Catalog"' not in code:
    code = must_replace(
        code,
        '    salesItems: "Sales_Items",\n    finance: "Finance_Ledger",\n',
        '    salesItems: "Sales_Items",\n'
        '    catalog: "Product_Catalog",\n'
        '    quotes: "Quotes",\n'
        '    quoteItems: "Quote_Items",\n'
        '    finance: "Finance_Ledger",\n',
        "new sales sheets",
    )

if 'Product_Catalog: "CAT"' not in code:
    code = must_replace(
        code,
        '    Sales_Items: "SIT",\n    Finance_Ledger: "TXN",\n',
        '    Sales_Items: "SIT",\n'
        '    Product_Catalog: "CAT",\n'
        '    Quotes: "QUO",\n'
        '    Quote_Items: "QIT",\n'
        '    Finance_Ledger: "TXN",\n',
        "new sales prefixes",
    )


# ==========================================================
# 2. Expand Sales_Items + add Catalog/Quote schemas
# ==========================================================

old_sales_items = '''const FIXXIR_SALES_ITEM_HEADERS = Object.freeze([
  "Sales_Item_ID",
  "Sales_ID",
  "Product_ID",
  "SKU",
  "Product_Name",
  "Quantity",
  "Unit_Price",
  "Unit_Cost",
  "Line_Total",
  "Cost_Total",
  "IMEI_or_Serial",
  "Notes",
]);
'''

new_sales_items = '''const FIXXIR_SALES_ITEM_HEADERS = Object.freeze([
  "Sales_Item_ID",
  "Sales_ID",
  "Item_Source",
  "Catalog_ID",
  "Inventory_ID",
  "Product_ID",
  "SKU",
  "Product_Name",
  "Quantity",
  "Unit_Price",
  "Unit_Cost",
  "Cost_Status",
  "Line_Total",
  "Cost_Total",
  "IMEI_or_Serial",
  "Notes",
]);

const FIXXIR_CATALOG_HEADERS = Object.freeze([
  "Catalog_ID",
  "SKU",
  "Product_Name",
  "Category",
  "Brand",
  "Model",
  "Variant",
  "Default_Price",
  "Default_Cost",
  "Serialized",
  "Status",
  "Date_Created",
  "Last_Updated",
  "Notes",
]);

const FIXXIR_QUOTE_HEADERS = Object.freeze([
  "Quote_ID",
  "Date",
  "Customer_ID",
  "Quote_Status",
  "Pricing_Status",
  "Subtotal",
  "Discount_Amount",
  "Total_Amount",
  "Valid_Until",
  "Converted_Sales_ID",
  "Created_By",
  "Last_Updated",
  "Notes",
]);

const FIXXIR_QUOTE_ITEM_HEADERS = Object.freeze([
  "Quote_Item_ID",
  "Quote_ID",
  "Item_Source",
  "Catalog_ID",
  "Inventory_ID",
  "SKU",
  "Product_Name",
  "Quantity",
  "Unit_Price",
  "Price_Status",
  "Unit_Cost_Estimate",
  "Cost_Status",
  "Line_Total",
  "IMEI_or_Serial",
  "Notes",
]);
'''

if 'FIXXIR_CATALOG_HEADERS' not in code:
    code = must_replace(
        code,
        old_sales_items,
        new_sales_items,
        "flexible sales schemas",
    )


# ==========================================================
# 3. Expand ensureSalesSheets_ so upgrades are automatic
# ==========================================================

old_ensure = '''function ensureSalesSheets_(ss) {
  ss = ss || getSpreadsheet_();

  ensureSheetColumns_(
    ss,
    FIXXIR.sheets.salesOrders,
    FIXXIR_SALES_ORDER_HEADERS,
  );

  ensureSheetColumns_(
    ss,
    FIXXIR.sheets.salesItems,
    FIXXIR_SALES_ITEM_HEADERS,
  );
}
'''

new_ensure = '''function ensureSalesSheets_(ss) {
  ss = ss || getSpreadsheet_();

  ensureSheetColumns_(
    ss,
    FIXXIR.sheets.salesOrders,
    FIXXIR_SALES_ORDER_HEADERS,
  );

  ensureSheetColumns_(
    ss,
    FIXXIR.sheets.salesItems,
    FIXXIR_SALES_ITEM_HEADERS,
  );

  ensureSheetColumns_(
    ss,
    FIXXIR.sheets.catalog,
    FIXXIR_CATALOG_HEADERS,
  );

  ensureSheetColumns_(
    ss,
    FIXXIR.sheets.quotes,
    FIXXIR_QUOTE_HEADERS,
  );

  ensureSheetColumns_(
    ss,
    FIXXIR.sheets.quoteItems,
    FIXXIR_QUOTE_ITEM_HEADERS,
  );

  migrateLegacySalesCostStatus_(ss);
}
'''

if 'FIXXIR.sheets.quoteItems' not in code.split('function ensureSalesSheets_(ss)',1)[1]:
    code = must_replace(code, old_ensure, new_ensure, "sales sheet upgrader")


# ==========================================================
# 4. Profit calculations: preserve Pending/Estimated costs
# ==========================================================

old_bucket = '''      itemMap[id] = {
        itemCount: 0,
        quantity: 0,
        costTotal: 0,
        names: [],
        search: [],
      };
'''

new_bucket = '''      itemMap[id] = {
        itemCount: 0,
        quantity: 0,
        costTotal: 0,
        allCostsKnown: true,
        hasEstimatedCost: false,
        names: [],
        search: [],
      };
'''

if 'allCostsKnown: true' not in code:
    code = must_replace(code, old_bucket, new_bucket, "sales cost-state bucket")

old_cost_add = '''    bucket.itemCount += 1;
    bucket.quantity += number_(item.Quantity);
    bucket.costTotal += number_(item.Cost_Total) ||
      number_(item.Unit_Cost) * number_(item.Quantity);
'''

new_cost_add = '''    bucket.itemCount += 1;
    bucket.quantity += number_(item.Quantity);

    const itemCostStatus = clean_(item.Cost_Status) ||
      (hasValue_(item.Unit_Cost) ? "Known" : "Pending");

    if (itemCostStatus !== "Known") bucket.allCostsKnown = false;
    if (itemCostStatus === "Estimated") bucket.hasEstimatedCost = true;

    if (hasValue_(item.Cost_Total)) {
      bucket.costTotal += number_(item.Cost_Total);
    } else if (hasValue_(item.Unit_Cost)) {
      bucket.costTotal += number_(item.Unit_Cost) * number_(item.Quantity);
    }
'''

if 'const itemCostStatus = clean_(item.Cost_Status)' not in code:
    code = must_replace(code, old_cost_add, new_cost_add, "sales cost accumulation")

old_default_summary = '''    const itemSummary = itemMap[order.Sales_ID] || {
      itemCount: 0,
      quantity: 0,
      costTotal: 0,
      names: [],
      search: [],
    };
'''

new_default_summary = '''    const itemSummary = itemMap[order.Sales_ID] || {
      itemCount: 0,
      quantity: 0,
      costTotal: 0,
      allCostsKnown: true,
      hasEstimatedCost: false,
      names: [],
      search: [],
    };
'''

if 'hasEstimatedCost: false' not in code.split('const itemSummary = itemMap[order.Sales_ID]',1)[1][:400]:
    code = must_replace(code, old_default_summary, new_default_summary, "default sales cost state")

old_row_calc = '''      Payment_Status_Calc: salePaymentStatus_(total, paid),
      Cost_Total_Calc: itemSummary.costTotal,
      Gross_Profit_Calc: total - itemSummary.costTotal,
'''

new_row_calc = '''      Payment_Status_Calc: salePaymentStatus_(total, paid),
      Cost_Total_Calc: itemSummary.costTotal,
      Cost_Status_Calc: itemSummary.allCostsKnown
        ? "Known"
        : itemSummary.hasEstimatedCost
          ? "Estimated / Pending"
          : "Pending",
      Gross_Profit_Calc: itemSummary.allCostsKnown
        ? total - itemSummary.costTotal
        : "",
'''

if 'Cost_Status_Calc:' not in code:
    code = must_replace(code, old_row_calc, new_row_calc, "sales row profit state")

old_sales_summary = '''      grossProfit: active.reduce((sum, row) => sum + number_(row.Gross_Profit_Calc), 0),
'''

new_sales_summary = '''      grossProfit: active
        .filter((row) => row.Cost_Status_Calc === "Known")
        .reduce((sum, row) => sum + number_(row.Gross_Profit_Calc), 0),
      profitPending: active.filter((row) => row.Cost_Status_Calc !== "Known").length,
'''

if 'profitPending:' not in code:
    code = must_replace(code, old_sales_summary, new_sales_summary, "sales summary pending profit")

old_getsale_cost = '''  const total = number_(order.Total_Amount);
  const costTotal = items.reduce(
    (sum, item) =>
      sum +
      (number_(item.Cost_Total) ||
        number_(item.Unit_Cost) * number_(item.Quantity)),
    0,
  );
'''

new_getsale_cost = '''  const total = number_(order.Total_Amount);
  let costTotal = 0;
  let allCostsKnown = true;
  let hasEstimatedCost = false;

  items.forEach((item) => {
    const status = clean_(item.Cost_Status) ||
      (hasValue_(item.Unit_Cost) ? "Known" : "Pending");

    if (status !== "Known") allCostsKnown = false;
    if (status === "Estimated") hasEstimatedCost = true;

    if (hasValue_(item.Cost_Total)) {
      costTotal += number_(item.Cost_Total);
    } else if (hasValue_(item.Unit_Cost)) {
      costTotal += number_(item.Unit_Cost) * number_(item.Quantity);
    }
  });
'''

if 'let allCostsKnown = true;' not in code.split('function getSale(salesId)',1)[1][:2500]:
    code = must_replace(code, old_getsale_cost, new_getsale_cost, "sale detail cost state")

old_getsale_summary = '''      costTotal,
      grossProfit: total - costTotal,
'''

new_getsale_summary = '''      costTotal,
      costStatus: allCostsKnown
        ? "Known"
        : hasEstimatedCost
          ? "Estimated / Pending"
          : "Pending",
      grossProfit: allCostsKnown ? total - costTotal : "",
'''

if 'costStatus: allCostsKnown' not in code:
    code = must_replace(code, old_getsale_summary, new_getsale_summary, "sale detail profit state")


# ==========================================================
# 5. createSale: ad-hoc/catalog items and blank cost support
# ==========================================================

old_clean_items = '''  const cleanItems = items.map((item, index) => {
    const name = clean_(item.Product_Name);
    const quantity = number_(item.Quantity);
    const unitPrice = number_(item.Unit_Price);
    const unitCost = number_(item.Unit_Cost);
    const serial = clean_(item.IMEI_or_Serial);

    if (!name) throw new Error(`Item ${index + 1}: product name is required.`);
    if (!(quantity > 0)) {
      throw new Error(`Item ${index + 1}: quantity must be greater than zero.`);
    }
    if (unitPrice < 0) {
      throw new Error(`Item ${index + 1}: unit price cannot be negative.`);
    }
    if (unitCost < 0) {
      throw new Error(`Item ${index + 1}: unit cost cannot be negative.`);
    }
    if (serial && quantity !== 1) {
      throw new Error(
        `Item ${index + 1}: serialized/IMEI devices must be entered one unit per line.`,
      );
    }

    return {
      Product_ID: clean_(item.Product_ID),
      SKU: clean_(item.SKU),
      Product_Name: name,
      Quantity: quantity,
      Unit_Price: unitPrice,
      Unit_Cost: unitCost,
      Line_Total: quantity * unitPrice,
      Cost_Total: quantity * unitCost,
      IMEI_or_Serial: serial,
      Notes: clean_(item.Notes),
    };
  });
'''

new_clean_items = '''  const cleanItems = items.map((item, index) => {
    const name = clean_(item.Product_Name);
    const quantity = number_(item.Quantity);
    const unitPrice = number_(item.Unit_Price);
    const unitCostRaw = clean_(item.Unit_Cost);
    const hasCost = unitCostRaw !== "";
    const unitCost = hasCost ? number_(unitCostRaw) : "";
    const serial = clean_(item.IMEI_or_Serial);

    if (!name) throw new Error(`Item ${index + 1}: product name is required.`);
    if (!(quantity > 0)) {
      throw new Error(`Item ${index + 1}: quantity must be greater than zero.`);
    }
    if (unitPrice < 0) {
      throw new Error(`Item ${index + 1}: unit price cannot be negative.`);
    }
    if (hasCost && unitCost < 0) {
      throw new Error(`Item ${index + 1}: unit cost cannot be negative.`);
    }
    if (serial && quantity !== 1) {
      throw new Error(
        `Item ${index + 1}: serialized/IMEI devices must be entered one unit per line.`,
      );
    }

    let catalogId = clean_(item.Catalog_ID);
    if (!catalogId && truthy_(item.Save_to_Catalog)) {
      catalogId = getOrCreateCatalogProduct_({
        SKU: item.SKU,
        Product_Name: name,
        Default_Price: unitPrice,
        Default_Cost: hasCost ? unitCost : "",
        Serialized: serial ? "Yes" : "No",
      }).Catalog_ID;
    }

    const requestedCostStatus = clean_(item.Cost_Status);
    const costStatus = !hasCost
      ? "Pending"
      : ["Known", "Estimated"].includes(requestedCostStatus)
        ? requestedCostStatus
        : "Known";

    const itemSource = clean_(item.Item_Source) ||
      (clean_(item.Inventory_ID) ? "Inventory" : catalogId ? "Catalog" : "Ad-hoc");

    return {
      Item_Source: itemSource,
      Catalog_ID: catalogId,
      Inventory_ID: clean_(item.Inventory_ID),
      Product_ID: clean_(item.Product_ID),
      SKU: clean_(item.SKU),
      Product_Name: name,
      Quantity: quantity,
      Unit_Price: unitPrice,
      Unit_Cost: unitCost,
      Cost_Status: costStatus,
      Line_Total: quantity * unitPrice,
      Cost_Total: hasCost ? quantity * unitCost : "",
      IMEI_or_Serial: serial,
      Notes: clean_(item.Notes),
    };
  });
'''

if 'const unitCostRaw = clean_(item.Unit_Cost);' not in code:
    code = must_replace(code, old_clean_items, new_clean_items, "flexible createSale items")


# ==========================================================
# 6. Catalog + Quote backend + late cost update
# ==========================================================

backend_anchor = 'function postFinance(payload) {\n'

phase2_backend = r'''/* ---------------- Flexible Sales / Catalog / Quotes ---------------- */

function migrateLegacySalesCostStatus_(ss) {
  const sh = (ss || getSpreadsheet_()).getSheetByName(FIXXIR.sheets.salesItems);
  if (!sh || sh.getLastRow() < 2) return;

  const values = sh.getDataRange().getValues();
  const headers = values[0].map(String);
  const unitCostCol = headers.indexOf("Unit_Cost");
  const costTotalCol = headers.indexOf("Cost_Total");
  const statusCol = headers.indexOf("Cost_Status");

  if (statusCol < 0 || unitCostCol < 0) return;

  let changed = false;
  for (let i = 1; i < values.length; i += 1) {
    if (String(values[i][statusCol] || "").trim()) continue;

    const unitCost = number_(values[i][unitCostCol]);
    if (unitCost > 0) {
      values[i][statusCol] = "Known";
    } else {
      // Sales Phase 1 converted blank costs to numeric zero. Treat those
      // legacy zeroes as unknown until staff explicitly records actual cost.
      values[i][unitCostCol] = "";
      if (costTotalCol >= 0) values[i][costTotalCol] = "";
      values[i][statusCol] = "Pending";
    }
    changed = true;
  }

  if (changed) {
    sh.getRange(1, 1, values.length, values[0].length).setValues(values);
  }
}

function searchSalesProducts(query) {
  assertAuthorized_();
  ensureSalesSheets_(getSpreadsheet_());

  const q = clean_(query).toLowerCase();
  if (!q) return [];

  return getRecords_(FIXXIR.sheets.catalog)
    .filter((item) => !item.Status || item.Status === "Active")
    .filter((item) =>
      [
        item.Catalog_ID,
        item.SKU,
        item.Product_Name,
        item.Category,
        item.Brand,
        item.Model,
        item.Variant,
      ].some((value) =>
        String(value || "").toLowerCase().includes(q),
      ),
    )
    .slice(0, 20)
    .map((item) => Object.assign({}, item, { _Source: "Catalog" }));
}

function saveCatalogProduct(payload) {
  assertAuthorized_();
  ensureSalesSheets_(getSpreadsheet_());
  return getOrCreateCatalogProduct_(payload || {});
}

function getOrCreateCatalogProduct_(payload) {
  payload = payload || {};

  const existingId = clean_(payload.Catalog_ID);
  if (existingId) {
    const existing = findById_(FIXXIR.sheets.catalog, "Catalog_ID", existingId);
    if (!existing) throw new Error("Catalog item not found: " + existingId);
    return existing;
  }

  const name = clean_(payload.Product_Name);
  if (!name) throw new Error("Product name is required to save a catalog item.");

  const sku = clean_(payload.SKU);
  const catalog = getRecords_(FIXXIR.sheets.catalog);

  const existing = catalog.find((item) => {
    if (sku && clean_(item.SKU).toLowerCase() === sku.toLowerCase()) return true;
    return clean_(item.Product_Name).toLowerCase() === name.toLowerCase();
  });

  if (existing) return existing;

  const id = generateId_(FIXXIR.sheets.catalog);
  const now = new Date();

  appendRecord_(FIXXIR.sheets.catalog, {
    Catalog_ID: id,
    SKU: sku,
    Product_Name: name,
    Category: clean_(payload.Category),
    Brand: clean_(payload.Brand),
    Model: clean_(payload.Model),
    Variant: clean_(payload.Variant),
    Default_Price: numberOrBlank_(payload.Default_Price),
    Default_Cost: numberOrBlank_(payload.Default_Cost),
    Serialized: clean_(payload.Serialized) || "No",
    Status: "Active",
    Date_Created: now,
    Last_Updated: now,
    Notes: clean_(payload.Notes),
  });

  return findById_(FIXXIR.sheets.catalog, "Catalog_ID", id);
}

function updateSaleItemCost(payload) {
  assertAuthorized_();
  payload = payload || {};

  const itemId = clean_(payload.Sales_Item_ID);
  if (!itemId) throw new Error("Sales_Item_ID is required.");

  const item = findById_(FIXXIR.sheets.salesItems, "Sales_Item_ID", itemId);
  if (!item) throw new Error("Sale item not found: " + itemId);

  const raw = clean_(payload.Unit_Cost);
  if (!raw) throw new Error("Enter the actual unit cost.");

  const unitCost = number_(raw);
  if (unitCost < 0) throw new Error("Unit cost cannot be negative.");

  updateRecordById_(FIXXIR.sheets.salesItems, "Sales_Item_ID", itemId, {
    Unit_Cost: unitCost,
    Cost_Total: unitCost * number_(item.Quantity),
    Cost_Status: "Known",
  });

  return getSale(item.Sales_ID);
}

function listQuotes(filters) {
  assertAuthorized_();
  ensureSalesSheets_(getSpreadsheet_());
  filters = filters || {};

  const customers = objectMap_(getRecords_(FIXXIR.sheets.customers), "Customer_ID");
  const quoteItems = getRecords_(FIXXIR.sheets.quoteItems);
  const itemMap = {};

  quoteItems.forEach((item) => {
    if (!itemMap[item.Quote_ID]) itemMap[item.Quote_ID] = [];
    itemMap[item.Quote_ID].push(item);
  });

  let rows = getRecords_(FIXXIR.sheets.quotes).map((quote) => {
    const customer = customers[quote.Customer_ID] || {};
    const items = itemMap[quote.Quote_ID] || [];

    return Object.assign({}, quote, {
      Customer_Name: customer.Full_Name || "",
      Customer_Phone: customer.Phone_Primary || "",
      Item_Count_Calc: items.length,
      Item_Summary: items.map((item) => item.Product_Name).filter(Boolean).slice(0, 3).join(", "),
    });
  });

  const q = clean_(filters.q).toLowerCase();
  const status = clean_(filters.status);

  if (q) {
    rows = rows.filter((row) =>
      [
        row.Quote_ID,
        row.Customer_Name,
        row.Customer_Phone,
        row.Item_Summary,
      ].some((value) => String(value || "").toLowerCase().includes(q)),
    );
  }

  if (status) rows = rows.filter((row) => row.Quote_Status === status);

  rows.sort((a, b) => String(b.Date || "").localeCompare(String(a.Date || "")));
  return rows.slice(0, 100);
}

function getQuote(quoteId) {
  assertAuthorized_();
  ensureSalesSheets_(getSpreadsheet_());

  const id = clean_(quoteId);
  if (!id) throw new Error("Quote ID is required.");

  const quote = findById_(FIXXIR.sheets.quotes, "Quote_ID", id);
  if (!quote) throw new Error("Quote not found: " + id);

  const customer = quote.Customer_ID
    ? findById_(FIXXIR.sheets.customers, "Customer_ID", quote.Customer_ID)
    : null;

  const items = getRecords_(FIXXIR.sheets.quoteItems)
    .filter((item) => item.Quote_ID === id);

  return { quote, customer, items };
}

function saveQuote(payload) {
  assertAuthorized_();
  ensureSalesSheets_(getSpreadsheet_());
  payload = payload || {};

  let items = payload.Items || [];
  if (typeof items === "string") {
    try {
      items = JSON.parse(items);
    } catch (error) {
      throw new Error("Quote items could not be read.");
    }
  }

  if (!Array.isArray(items) || !items.length) {
    throw new Error("Add at least one item to the quote.");
  }

  let customerId = clean_(payload.Customer_ID);

  if (!customerId) {
    requireFields_(payload, ["Customer_Name", "Customer_Phone"]);

    const customer = createCustomer({
      Customer_Type: "Individual",
      Full_Name: payload.Customer_Name,
      Phone_Primary: payload.Customer_Phone,
      Phone_Alternate: payload.Customer_Phone_Alternate,
      Email: payload.Customer_Email,
      Address: payload.Customer_Address,
    });

    customerId = customer.Customer_ID;
  } else if (!findById_(FIXXIR.sheets.customers, "Customer_ID", customerId)) {
    throw new Error("Selected customer no longer exists.");
  }

  let pricingPending = false;

  const cleanItems = items.map((item, index) => {
    const name = clean_(item.Product_Name);
    const quantity = number_(item.Quantity);
    const priceRaw = clean_(item.Unit_Price);
    const priceKnown = priceRaw !== "";
    const unitPrice = priceKnown ? number_(priceRaw) : "";
    const costRaw = clean_(item.Unit_Cost_Estimate);
    const costKnown = costRaw !== "";
    const costEstimate = costKnown ? number_(costRaw) : "";
    const serial = clean_(item.IMEI_or_Serial);

    if (!name) throw new Error(`Item ${index + 1}: product name is required.`);
    if (!(quantity > 0)) throw new Error(`Item ${index + 1}: quantity must be greater than zero.`);
    if (priceKnown && unitPrice < 0) throw new Error(`Item ${index + 1}: price cannot be negative.`);
    if (costKnown && costEstimate < 0) throw new Error(`Item ${index + 1}: cost estimate cannot be negative.`);
    if (serial && quantity !== 1) {
      throw new Error(`Item ${index + 1}: serialized/IMEI devices must be entered one unit per line.`);
    }

    if (!priceKnown) pricingPending = true;

    let catalogId = clean_(item.Catalog_ID);
    if (!catalogId && truthy_(item.Save_to_Catalog)) {
      catalogId = getOrCreateCatalogProduct_({
        SKU: item.SKU,
        Product_Name: name,
        Default_Price: priceKnown ? unitPrice : "",
        Default_Cost: costKnown ? costEstimate : "",
        Serialized: serial ? "Yes" : "No",
      }).Catalog_ID;
    }

    return {
      Item_Source: clean_(item.Item_Source) ||
        (clean_(item.Inventory_ID) ? "Inventory" : catalogId ? "Catalog" : "Ad-hoc"),
      Catalog_ID: catalogId,
      Inventory_ID: clean_(item.Inventory_ID),
      SKU: clean_(item.SKU),
      Product_Name: name,
      Quantity: quantity,
      Unit_Price: unitPrice,
      Price_Status: priceKnown ? "Known" : "Pending",
      Unit_Cost_Estimate: costEstimate,
      Cost_Status: costKnown ? "Estimated" : "Pending",
      Line_Total: priceKnown ? quantity * unitPrice : "",
      IMEI_or_Serial: serial,
      Notes: clean_(item.Notes),
    };
  });

  const knownSubtotal = cleanItems.reduce(
    (sum, item) => sum + (hasValue_(item.Line_Total) ? number_(item.Line_Total) : 0),
    0,
  );

  const discount = number_(payload.Discount_Amount);
  if (discount < 0) throw new Error("Discount cannot be negative.");
  if (!pricingPending && discount > knownSubtotal) {
    throw new Error("Discount cannot exceed the quote subtotal.");
  }
  if (pricingPending && discount > 0) {
    throw new Error("Finish pricing all quote items before applying a discount.");
  }

  let quoteId = clean_(payload.Quote_ID);
  const now = new Date();
  const pricingStatus = pricingPending ? "Pending" : "Complete";
  const requestedStatus = clean_(payload.Quote_Status);
  const quoteStatus = requestedStatus || (pricingPending ? "Pricing" : "Draft");

  const quoteRecord = {
    Date: parseDate_(payload.Date) || now,
    Customer_ID: customerId,
    Quote_Status: quoteStatus,
    Pricing_Status: pricingStatus,
    Subtotal: pricingPending ? "" : knownSubtotal,
    Discount_Amount: discount,
    Total_Amount: pricingPending ? "" : knownSubtotal - discount,
    Valid_Until: parseDate_(payload.Valid_Until),
    Created_By: currentUser_(),
    Last_Updated: now,
    Notes: clean_(payload.Notes),
  };

  if (quoteId) {
    const existing = findById_(FIXXIR.sheets.quotes, "Quote_ID", quoteId);
    if (!existing) throw new Error("Quote not found: " + quoteId);
    if (existing.Converted_Sales_ID) {
      throw new Error("A converted quote cannot be edited.");
    }

    quoteRecord.Date = existing.Date || quoteRecord.Date;
    quoteRecord.Created_By = existing.Created_By || currentUser_();
    quoteRecord.Converted_Sales_ID = existing.Converted_Sales_ID || "";
    updateRecordById_(FIXXIR.sheets.quotes, "Quote_ID", quoteId, quoteRecord);
    deleteRowsByField_(FIXXIR.sheets.quoteItems, "Quote_ID", quoteId);
  } else {
    quoteId = generateId_(FIXXIR.sheets.quotes);
    appendRecord_(FIXXIR.sheets.quotes, Object.assign({ Quote_ID: quoteId }, quoteRecord));
  }

  cleanItems.forEach((item) => {
    appendRecord_(FIXXIR.sheets.quoteItems, Object.assign({
      Quote_Item_ID: generateId_(FIXXIR.sheets.quoteItems),
      Quote_ID: quoteId,
    }, item));
  });

  return getQuote(quoteId);
}

function convertQuoteToSale(quoteId) {
  assertAuthorized_();

  const data = getQuote(quoteId);
  const quote = data.quote;

  if (quote.Converted_Sales_ID) {
    return getSale(quote.Converted_Sales_ID);
  }

  if (quote.Pricing_Status !== "Complete") {
    throw new Error("Finish pricing every quote item before converting it to a sale.");
  }

  if (["Declined", "Expired"].includes(quote.Quote_Status)) {
    throw new Error("This quote cannot be converted in its current status.");
  }

  const sale = createSale({
    Customer_ID: quote.Customer_ID,
    Sales_Status: "Pending Fulfilment",
    Discount_Amount: quote.Discount_Amount,
    Initial_Payment: 0,
    Notes: [
      "Converted from " + quote.Quote_ID,
      quote.Notes || "",
    ].filter(Boolean).join("\n"),
    Items: data.items.map((item) => ({
      Item_Source: item.Item_Source,
      Catalog_ID: item.Catalog_ID,
      Inventory_ID: item.Inventory_ID,
      SKU: item.SKU,
      Product_Name: item.Product_Name,
      Quantity: item.Quantity,
      Unit_Price: item.Unit_Price,
      // Quote costs are estimates. Do not silently treat them as actual COGS.
      Unit_Cost: "",
      Cost_Status: "Pending",
      IMEI_or_Serial: item.IMEI_or_Serial,
      Notes: item.Notes,
    })),
  });

  updateRecordById_(FIXXIR.sheets.quotes, "Quote_ID", quote.Quote_ID, {
    Quote_Status: "Converted",
    Converted_Sales_ID: sale.order.Sales_ID,
    Last_Updated: new Date(),
  });

  return sale;
}

function deleteRowsByField_(sheetName, fieldName, value) {
  const sh = getSheet_(sheetName);
  const values = sh.getDataRange().getValues();
  if (values.length < 2) return;

  const headers = values[0].map(String);
  const col = headers.indexOf(fieldName);
  if (col < 0) throw new Error("Column not found: " + fieldName);

  for (let row = values.length - 1; row >= 1; row -= 1) {
    if (String(values[row][col]) === String(value)) {
      sh.deleteRow(row + 1);
    }
  }
}

function hasValue_(value) {
  return value !== "" && value !== null && value !== undefined;
}

function truthy_(value) {
  return value === true || ["true", "1", "yes", "on"].includes(
    String(value || "").trim().toLowerCase(),
  );
}

'''

if 'function saveQuote(payload)' not in code:
    code = must_replace(code, backend_anchor, phase2_backend + backend_anchor, "Phase 2 backend")


# ==========================================================
# 7. UI globals
# ==========================================================

globals_anchor = '''  let SALE_TIMER = null;
  let SALE_CUSTOMER_TIMER = null;
  let SALE_ITEM_SEQ = 0;
'''

globals_replacement = '''  let SALE_TIMER = null;
  let SALE_CUSTOMER_TIMER = null;
  let SALE_PRODUCT_TIMER = null;
  let SALE_ITEM_SEQ = 0;
  let CURRENT_QUOTE = null;
  let QUOTE_CUSTOMER_TIMER = null;
  let QUOTE_PRODUCT_TIMER = null;
  let QUOTE_ITEM_SEQ = 0;
'''

if 'let CURRENT_QUOTE = null;' not in html:
    html = must_replace(html, globals_anchor, globals_replacement, "Phase 2 UI globals")


# ==========================================================
# 8. Sales page: add Quotes panel/button and Pending Fulfilment
# ==========================================================

html = html.replace(
    '<div class="actions"><button class="btn primary" onclick="openNewSale()">+ New Sale</button></div>',
    '<div class="actions"><button class="btn" onclick="openNewQuote()">+ New Quote</button><button class="btn primary" onclick="openNewSale()">+ New Sale</button></div>',
    1,
)

quotes_panel_anchor = '''      <div class="grid kpis" id="salesKpis">
        ${kpi('Orders','—','Sales orders')}
        ${kpi('Sales value','—','Completed/non-cancelled sales')}
        ${kpi('Outstanding','—','Customer balances')}
        ${kpi('Gross profit','—','Sales less recorded item cost')}
      </div>
      <div class="filters" style="margin-bottom:14px">
'''

quotes_panel_replacement = '''      <div class="grid kpis" id="salesKpis">
        ${kpi('Orders','—','Sales orders')}
        ${kpi('Sales value','—','Completed/non-cancelled sales')}
        ${kpi('Outstanding','—','Customer balances')}
        ${kpi('Gross profit','—','Known-cost sales only')}
      </div>
      <div class="card section" style="margin-bottom:18px">
        <div class="section-head"><h3>Quotes & price requests</h3><button class="btn small" onclick="openNewQuote()">+ New Quote</button></div>
        <div id="quotesList"><div class="empty">Loading quotes…</div></div>
      </div>
      <div class="filters" style="margin-bottom:14px">
'''

if 'id="quotesList"' not in html:
    html = must_replace(html, quotes_panel_anchor, quotes_panel_replacement, "Quotes panel")

html = html.replace(
    '<option>Completed</option><option>Draft</option><option>Cancelled</option>',
    '<option>Pending Fulfilment</option><option>Completed</option><option>Draft</option><option>Cancelled</option>',
)

html = html.replace(
    '    await loadSales();\n  }\n\n  function debouncedSalesLoad()',
    '    await Promise.all([loadSales(),loadQuotes()]);\n  }\n\n  function debouncedSalesLoad()',
    1,
)

old_kpi_profit = "${kpi('Gross profit',money(s.grossProfit),'Sales less recorded item cost')}"
new_kpi_profit = "${kpi('Gross profit',money(s.grossProfit),s.profitPending?`${s.profitPending} sale(s) pending actual cost`:'All sale costs known')}"
html = html.replace(old_kpi_profit, new_kpi_profit, 1)


# ==========================================================
# 9. Sale item row: catalog search + optional cost + save catalog
# ==========================================================

old_sale_row = r'''  function addSaleItemRow(item={}){
    SALE_ITEM_SEQ+=1;
    const row=document.createElement('div');
    row.className='card section sale-item-row';
    row.style.marginBottom='10px';
    row.dataset.row=String(SALE_ITEM_SEQ);

    row.innerHTML=`
      <div class="section-head">
        <h3>Item ${SALE_ITEM_SEQ}</h3>
        <button class="btn small" type="button" onclick="removeSaleItemRow(this)">Remove</button>
      </div>
      <div class="form-grid">
        <div><label class="required">Product</label><input class="input" data-field="Product_Name" value="${escAttr(item.Product_Name||'')}" placeholder="iPhone 13, AirPods, HP EliteBook…"></div>
        <div><label>SKU</label><input class="input" data-field="SKU" value="${escAttr(item.SKU||'')}"></div>
        <div><label class="required">Quantity</label><input class="input" type="number" min="1" step="1" data-field="Quantity" value="${escAttr(item.Quantity||1)}" oninput="recalcSale()"></div>
        <div><label class="required">Unit price (₦)</label><input class="input" type="number" min="0" step="1" data-field="Unit_Price" value="${escAttr(item.Unit_Price||'')}" oninput="recalcSale()"></div>
        <div><label>Unit cost (₦)</label><input class="input" type="number" min="0" step="1" data-field="Unit_Cost" value="${escAttr(item.Unit_Cost||'')}" oninput="recalcSale()"></div>
        <div><label>IMEI / Serial</label><input class="input" data-field="IMEI_or_Serial" value="${escAttr(item.IMEI_or_Serial||'')}" placeholder="One serialized device per row"></div>
        <div class="full"><label>Item notes</label><input class="input" data-field="Notes" value="${escAttr(item.Notes||'')}"></div>
        <div class="full" style="text-align:right"><span class="muted">Line total:</span> <b class="sale-line-total">${money(0)}</b></div>
      </div>`;

    document.getElementById('saleItems').appendChild(row);
    recalcSale();
  }
'''

new_sale_row = r'''  function addSaleItemRow(item={}){
    SALE_ITEM_SEQ+=1;
    const row=document.createElement('div');
    row.className='card section sale-item-row';
    row.style.marginBottom='10px';
    row.dataset.row=String(SALE_ITEM_SEQ);
    row.dataset.catalogName=item.Product_Name||'';

    const initialCostStatus=item.Cost_Status||((item.Unit_Cost!==''&&item.Unit_Cost!=null)?'Known':'Pending');

    row.innerHTML=`
      <div class="section-head">
        <div><h3>Item ${SALE_ITEM_SEQ}</h3><span class="muted" data-role="source-label">${esc(item.Item_Source||'Ad-hoc')}</span></div>
        <button class="btn small" type="button" onclick="removeSaleItemRow(this)">Remove</button>
      </div>
      <div class="form-grid">
        <div class="full">
          <label class="required">Product</label>
          <input class="input" data-field="Product_Name" value="${escAttr(item.Product_Name||'')}" placeholder="Search catalog or type any item…" oninput="saleProductChanged(this);debouncedSalesProductSearch(this)">
          <div class="customer-results" data-role="product-results"></div>
          <input type="hidden" data-field="Catalog_ID" value="${escAttr(item.Catalog_ID||'')}">
          <input type="hidden" data-field="Inventory_ID" value="${escAttr(item.Inventory_ID||'')}">
          <input type="hidden" data-field="Item_Source" value="${escAttr(item.Item_Source||'Ad-hoc')}">
          <input type="hidden" data-field="Cost_Status" value="${escAttr(initialCostStatus)}">
        </div>
        <div><label>SKU</label><input class="input" data-field="SKU" value="${escAttr(item.SKU||'')}"></div>
        <div><label class="required">Quantity</label><input class="input" type="number" min="1" step="1" data-field="Quantity" value="${escAttr(item.Quantity||1)}" oninput="recalcSale()"></div>
        <div><label class="required">Selling price (₦)</label><input class="input" type="number" min="0" step="1" data-field="Unit_Price" value="${escAttr(item.Unit_Price??'')}" oninput="recalcSale()"></div>
        <div>
          <label>Actual unit cost (₦)</label>
          <input class="input" type="number" min="0" step="1" data-field="Unit_Cost" value="${escAttr(item.Unit_Cost??'')}" placeholder="Leave blank if unknown" oninput="saleCostChanged(this);recalcSale()">
          <div class="muted" style="font-size:11px;margin-top:4px" data-role="cost-label">${initialCostStatus==='Known'?'Actual cost recorded':initialCostStatus==='Estimated'?'Estimated cost — profit pending':'Unknown cost — profit pending'}</div>
        </div>
        <div><label>IMEI / Serial</label><input class="input" data-field="IMEI_or_Serial" value="${escAttr(item.IMEI_or_Serial||'')}" placeholder="One serialized device per row"></div>
        <div class="full"><label style="display:flex;gap:8px;align-items:center;font-weight:700"><input type="checkbox" data-field="Save_to_Catalog" ${item.Save_to_Catalog?'checked':''}> Save this item to Catalog for future searches</label></div>
        <div class="full"><label>Item notes</label><input class="input" data-field="Notes" value="${escAttr(item.Notes||'')}"></div>
        <div class="full" style="text-align:right"><span class="muted">Line total:</span> <b class="sale-line-total">${money(0)}</b></div>
      </div>`;

    document.getElementById('saleItems').appendChild(row);
    recalcSale();
  }
'''

if 'debouncedSalesProductSearch(this)' not in html:
    html = must_replace(html, old_sale_row, new_sale_row, "flexible sale item row")

old_sale_payload = r'''  function saleItemsPayload(){
    return [...document.querySelectorAll('.sale-item-row')].map(row=>{
      const get=(field)=>row.querySelector(`[data-field="${field}"]`)?.value||'';
      return {
        Product_Name:get('Product_Name'),
        SKU:get('SKU'),
        Quantity:get('Quantity'),
        Unit_Price:get('Unit_Price'),
        Unit_Cost:get('Unit_Cost'),
        IMEI_or_Serial:get('IMEI_or_Serial'),
        Notes:get('Notes'),
      };
    });
  }
'''

new_sale_payload = r'''  function saleItemsPayload(){
    return [...document.querySelectorAll('.sale-item-row')].map(row=>{
      const get=(field)=>row.querySelector(`[data-field="${field}"]`)?.value||'';
      const checked=(field)=>!!row.querySelector(`[data-field="${field}"]`)?.checked;
      return {
        Item_Source:get('Item_Source')||'Ad-hoc',
        Catalog_ID:get('Catalog_ID'),
        Inventory_ID:get('Inventory_ID'),
        Product_Name:get('Product_Name'),
        SKU:get('SKU'),
        Quantity:get('Quantity'),
        Unit_Price:get('Unit_Price'),
        Unit_Cost:get('Unit_Cost'),
        Cost_Status:get('Cost_Status'),
        IMEI_or_Serial:get('IMEI_or_Serial'),
        Save_to_Catalog:checked('Save_to_Catalog'),
        Notes:get('Notes'),
      };
    });
  }
'''

if "Catalog_ID:get('Catalog_ID')" not in html:
    html = must_replace(html, old_sale_payload, new_sale_payload, "sale item payload")


# ==========================================================
# 10. Sale detail: Pending profit + actual cost update
# ==========================================================

html = html.replace(
    '<div class="finance-row"><span>Recorded cost</span><b>${money(summary.costTotal)}</b></div>\n          <div class="finance-row big"><span>Gross profit</span><span>${money(summary.grossProfit)}</span></div>',
    '<div class="finance-row"><span>Recorded / estimated cost</span><b>${money(summary.costTotal)}</b></div>\n          <div class="finance-row"><span>Cost status</span><b>${esc(summary.costStatus||\'Pending\')}</b></div>\n          <div class="finance-row big"><span>Gross profit</span><span>${summary.costStatus===\'Known\'?money(summary.grossProfit):\'Pending cost\'}</span></div>',
    1,
)

old_items_table = r'''  function saleItemsTable(rows){
    if(!rows.length)return '<div class="empty" style="padding:16px">No sale items.</div>';

    return `<div class="table-wrap"><table>
      <thead><tr><th>Item</th><th>SKU</th><th>IMEI / Serial</th><th>Qty</th><th>Unit Price</th><th>Unit Cost</th><th>Total</th></tr></thead>
      <tbody>${rows.map(item=>`<tr>
        <td><b>${esc(item.Product_Name)}</b></td>
        <td>${esc(item.SKU||'')}</td>
        <td>${esc(item.IMEI_or_Serial||'')}</td>
        <td>${esc(item.Quantity)}</td>
        <td class="money">${money(item.Unit_Price)}</td>
        <td class="money">${money(item.Unit_Cost)}</td>
        <td class="money">${money(item.Line_Total)}</td>
      </tr>`).join('')}</tbody></table></div>`;
  }
'''

new_items_table = r'''  function saleItemsTable(rows){
    if(!rows.length)return '<div class="empty" style="padding:16px">No sale items.</div>';

    return `<div class="table-wrap"><table>
      <thead><tr><th>Item</th><th>Source</th><th>SKU</th><th>IMEI / Serial</th><th>Qty</th><th>Unit Price</th><th>Unit Cost</th><th>Cost Status</th><th>Total</th><th></th></tr></thead>
      <tbody>${rows.map(item=>`<tr>
        <td><b>${esc(item.Product_Name)}</b></td>
        <td>${esc(item.Item_Source||'Ad-hoc')}</td>
        <td>${esc(item.SKU||'')}</td>
        <td>${esc(item.IMEI_or_Serial||'')}</td>
        <td>${esc(item.Quantity)}</td>
        <td class="money">${money(item.Unit_Price)}</td>
        <td class="money">${hasDisplayValue(item.Unit_Cost)?money(item.Unit_Cost):'—'}</td>
        <td>${esc(item.Cost_Status||'Pending')}</td>
        <td class="money">${money(item.Line_Total)}</td>
        <td><button class="btn small" onclick='openSaleCostEditor(${JSON.stringify(item).replace(/'/g,"&#39;")})'>${item.Cost_Status==='Known'?'Edit cost':'Set cost'}</button></td>
      </tr>`).join('')}</tbody></table></div>`;
  }
'''

if 'openSaleCostEditor' not in html:
    html = must_replace(html, old_items_table, new_items_table, "sale item detail table")


# ==========================================================
# 11. Add Quote and Cost modals before finance modal
# ==========================================================

modal_anchor = '<div class="modal" id="financeModal">\n'

phase2_modals = r'''<div class="modal" id="saleCostModal">
  <div class="modal-box" style="width:min(520px,100%)">
    <div class="modal-head"><h3 id="saleCostTitle">Set actual cost</h3><button class="close" onclick="closeModal('saleCostModal')">×</button></div>
    <form id="saleCostForm" onsubmit="submitSaleCost(event)">
      <div class="modal-body">
        <input type="hidden" name="Sales_Item_ID" id="saleCostItemId">
        <label class="required">Actual unit cost (₦)</label>
        <input class="input" type="number" min="0" step="1" name="Unit_Cost" id="saleCostUnitCost" required>
        <div class="muted" style="font-size:12px;margin-top:8px">Use this when the actual procurement / landed unit cost becomes known.</div>
      </div>
      <div class="modal-foot"><button type="button" class="btn" onclick="closeModal('saleCostModal')">Cancel</button><button class="btn primary" type="submit">Save actual cost</button></div>
    </form>
  </div>
</div>

<div class="modal" id="quoteModal">
  <div class="modal-box" style="width:min(1100px,100%)">
    <div class="modal-head"><h3 id="quoteModalTitle">New Quote</h3><button class="close" onclick="closeModal('quoteModal')">×</button></div>
    <form id="quoteForm" onsubmit="submitQuote(event)">
      <div class="modal-body">
        <input type="hidden" name="Quote_ID" id="quoteId">
        <div class="section-head"><h3>Customer</h3><span class="muted" style="font-size:12px">A quote may include items not currently stocked or catalogued.</span></div>
        <div class="form-grid">
          <div class="full">
            <label>Find customer/contact</label>
            <input class="input" id="quoteCustomerSearch" placeholder="Name, phone, customer ID…" oninput="debouncedQuoteCustomerSearch(this.value)">
            <div class="customer-results" id="quoteCustomerResults"></div>
            <div class="selected-customer" id="selectedQuoteCustomer"></div>
            <input type="hidden" name="Customer_ID" id="selectedQuoteCustomerId">
            <input type="hidden" name="Customer_Phone_Alternate" id="quoteCustomerPhoneAlternate">
            <input type="hidden" name="Customer_Address" id="quoteCustomerAddress">
          </div>
          <div><label class="required">Customer name</label><input class="input" name="Customer_Name" id="quoteCustomerName" required></div>
          <div><label class="required">Phone</label><input class="input" name="Customer_Phone" id="quoteCustomerPhone" required></div>
          <div><label>Email</label><input class="input" name="Customer_Email" id="quoteCustomerEmail"></div>
          <div><label>Quote status</label><select class="select" name="Quote_Status" id="quoteStatus"><option>Pricing</option><option>Draft</option><option>Sent</option><option>Accepted</option><option>Declined</option><option>Expired</option></select></div>
          <div><label>Valid until</label><input class="input" type="date" name="Valid_Until" id="quoteValidUntil"></div>
          <div><label>Discount (₦)</label><input class="input" type="number" min="0" step="1" name="Discount_Amount" id="quoteDiscount" value="0" oninput="recalcQuote()"></div>
        </div>

        <div class="section-head" style="margin-top:24px">
          <div><h3>Quote items</h3><div class="muted" style="font-size:12px;margin-top:4px">Price and cost may be left blank while sourcing.</div></div>
          <button type="button" class="btn small" onclick="addQuoteItemRow()">+ Add item</button>
        </div>
        <div id="quoteItems"></div>

        <div class="form-grid" style="margin-top:20px">
          <div class="full">
            <div class="finance-box">
              <div class="finance-row"><span>Pricing</span><b id="quotePricingView">Pending</b></div>
              <div class="finance-row"><span>Subtotal</span><b id="quoteSubtotalView">Pending</b></div>
              <div class="finance-row"><span>Discount</span><b id="quoteDiscountView">₦0</b></div>
              <div class="finance-row big"><span>Total</span><span id="quoteTotalView">Pending</span></div>
            </div>
          </div>
          <div class="full"><label>Notes</label><textarea class="textarea" name="Notes" id="quoteNotes"></textarea></div>
        </div>
      </div>
      <div class="modal-foot"><button type="button" class="btn" onclick="closeModal('quoteModal')">Cancel</button><button class="btn primary" type="submit">Save quote</button></div>
    </form>
  </div>
</div>

<div class="modal" id="quoteDetailModal">
  <div class="modal-box" style="width:min(1050px,100%)">
    <div class="modal-head"><h3 id="quoteDetailTitle">Quote</h3><button class="close" onclick="closeModal('quoteDetailModal')">×</button></div>
    <div class="modal-body" id="quoteDetailBody"></div>
  </div>
</div>

'''

if 'id="quoteModal"' not in html:
    html = must_replace(html, modal_anchor, phase2_modals + modal_anchor, "quote/cost modals")


# ==========================================================
# 12. Add Phase 2 client functions before Finance page
# ==========================================================

client_anchor = '  function renderFinancePage() {\n'

phase2_client = r'''  function debouncedSalesProductSearch(input){
    clearTimeout(SALE_PRODUCT_TIMER);
    SALE_PRODUCT_TIMER=setTimeout(()=>searchSalesProductPicker(input),220);
  }

  async function searchSalesProductPicker(input){
    const row=input.closest('.sale-item-row');
    const box=row.querySelector('[data-role="product-results"]');
    const q=input.value.trim();

    if(!q){box.style.display='none';return;}

    try{
      const items=await server('searchSalesProducts',q);
      const rowId=row.dataset.row;

      box.innerHTML=items.length
        ? items.map(item=>`<div class="customer-result" onclick='selectSaleCatalogItem("${escAttr(rowId)}",${JSON.stringify(item).replace(/'/g,"&#39;")})'>
            <b>${esc(item.Product_Name)}</b><br>
            <span class="muted">${esc(item.Catalog_ID)}${item.SKU?' · '+esc(item.SKU):''}${hasDisplayValue(item.Default_Price)?' · '+money(item.Default_Price):''}</span>
          </div>`).join('')+
          `<div class="customer-result muted" onclick="useSaleItemAsAdhoc('${escAttr(rowId)}')">Use typed item as ad-hoc (no catalog required)</div>`
        : `<div class="customer-result muted" onclick="useSaleItemAsAdhoc('${escAttr(rowId)}')">No catalog match — use typed item as ad-hoc</div>`;

      box.style.display='block';
    }catch(e){toast(e.message,true)}
  }

  function selectSaleCatalogItem(rowId,item){
    const row=[...document.querySelectorAll('.sale-item-row')].find(r=>r.dataset.row===String(rowId));
    if(!row)return;

    setRowField(row,'Product_Name',item.Product_Name||'');
    setRowField(row,'SKU',item.SKU||'');
    setRowField(row,'Catalog_ID',item.Catalog_ID||'');
    setRowField(row,'Item_Source','Catalog');
    row.dataset.catalogName=item.Product_Name||'';

    if(!getRowField(row,'Unit_Price')&&hasDisplayValue(item.Default_Price)){
      setRowField(row,'Unit_Price',item.Default_Price);
    }

    if(!getRowField(row,'Unit_Cost')&&hasDisplayValue(item.Default_Cost)){
      setRowField(row,'Unit_Cost',item.Default_Cost);
      setRowField(row,'Cost_Status','Estimated');
      updateSaleCostLabel(row,'Estimated');
    }

    row.querySelector('[data-role="source-label"]').textContent='Catalog';
    row.querySelector('[data-role="product-results"]').style.display='none';
    recalcSale();
  }

  function useSaleItemAsAdhoc(rowId){
    const row=[...document.querySelectorAll('.sale-item-row')].find(r=>r.dataset.row===String(rowId));
    if(!row)return;
    setRowField(row,'Catalog_ID','');
    setRowField(row,'Inventory_ID','');
    setRowField(row,'Item_Source','Ad-hoc');
    row.dataset.catalogName='';
    row.querySelector('[data-role="source-label"]').textContent='Ad-hoc';
    row.querySelector('[data-role="product-results"]').style.display='none';
  }

  function saleProductChanged(input){
    const row=input.closest('.sale-item-row');
    if(row.dataset.catalogName&&input.value!==row.dataset.catalogName){
      setRowField(row,'Catalog_ID','');
      setRowField(row,'Item_Source','Ad-hoc');
      row.querySelector('[data-role="source-label"]').textContent='Ad-hoc';
    }
  }

  function saleCostChanged(input){
    const row=input.closest('.sale-item-row');
    const status=input.value.trim()===''?'Pending':'Known';
    setRowField(row,'Cost_Status',status);
    updateSaleCostLabel(row,status);
  }

  function updateSaleCostLabel(row,status){
    const label=row.querySelector('[data-role="cost-label"]');
    if(!label)return;
    label.textContent=status==='Known'
      ?'Actual cost recorded'
      :status==='Estimated'
        ?'Estimated cost — profit pending'
        :'Unknown cost — profit pending';
  }

  function setRowField(row,field,value){
    const el=row.querySelector(`[data-field="${field}"]`);
    if(el)el.value=value??'';
  }

  function getRowField(row,field){
    return row.querySelector(`[data-field="${field}"]`)?.value||'';
  }

  function hasDisplayValue(value){
    return value!==''&&value!==null&&value!==undefined;
  }

  function openSaleCostEditor(item){
    document.getElementById('saleCostForm').reset();
    document.getElementById('saleCostItemId').value=item.Sales_Item_ID;
    document.getElementById('saleCostUnitCost').value=hasDisplayValue(item.Unit_Cost)?item.Unit_Cost:'';
    document.getElementById('saleCostTitle').textContent=`Actual cost · ${item.Product_Name||item.Sales_Item_ID}`;
    document.getElementById('saleCostModal').classList.add('open');
  }

  async function submitSaleCost(e){
    e.preventDefault();
    showLoading(true);
    try{
      CURRENT_SALE=await server('updateSaleItemCost',formObject(e.target));
      closeModal('saleCostModal');
      renderSaleDetail(CURRENT_SALE);
      toast('Actual item cost updated');
      if(CURRENT_PAGE==='sales')await loadSales();
    }catch(err){toast(err.message,true)}finally{showLoading(false)}
  }

  async function loadQuotes(){
    const box=document.getElementById('quotesList');
    if(!box)return;

    try{
      const rows=await server('listQuotes',{});
      if(!rows.length){
        box.innerHTML='<div class="empty" style="padding:18px">No quotes yet.</div>';
        return;
      }

      box.innerHTML=`<div class="table-wrap"><table>
        <thead><tr><th>Quote</th><th>Customer</th><th>Items</th><th>Pricing</th><th>Total</th><th>Status</th></tr></thead>
        <tbody>${rows.slice(0,10).map(q=>`<tr class="clickable" onclick="openQuote('${escAttr(q.Quote_ID)}')">
          <td><b>${esc(q.Quote_ID)}</b><br><span class="muted">${dateOnly(q.Date)}</span></td>
          <td>${esc(q.Customer_Name)}<br><span class="muted">${esc(q.Customer_Phone)}</span></td>
          <td>${esc(q.Item_Summary||`${q.Item_Count_Calc||0} item(s)`)}</td>
          <td>${q.Pricing_Status==='Complete'?'<span class="status ready">Complete</span>':'<span class="status">Pending</span>'}</td>
          <td class="money">${q.Pricing_Status==='Complete'?money(q.Total_Amount):'Pending'}</td>
          <td>${statusBadge(q.Quote_Status)}</td>
        </tr>`).join('')}</tbody></table></div>`;
    }catch(e){box.innerHTML=`<div class="empty">${esc(e.message)}</div>`}
  }

  function openNewQuote(){
    CURRENT_QUOTE=null;
    const form=document.getElementById('quoteForm');
    form.reset();
    document.getElementById('quoteId').value='';
    document.getElementById('selectedQuoteCustomerId').value='';
    document.getElementById('selectedQuoteCustomer').style.display='none';
    document.getElementById('quoteCustomerResults').style.display='none';
    document.getElementById('quoteItems').innerHTML='';
    document.getElementById('quoteModalTitle').textContent='New Quote';
    document.getElementById('quoteStatus').value='Pricing';
    QUOTE_ITEM_SEQ=0;
    addQuoteItemRow();
    recalcQuote();
    document.getElementById('quoteModal').classList.add('open');
  }

  function debouncedQuoteCustomerSearch(q){
    clearTimeout(QUOTE_CUSTOMER_TIMER);
    QUOTE_CUSTOMER_TIMER=setTimeout(()=>searchQuoteCustomerPicker(q),280);
  }

  async function searchQuoteCustomerPicker(q){
    const box=document.getElementById('quoteCustomerResults');
    if(!q.trim()){box.style.display='none';return;}

    try{
      const rows=await server('searchCustomerSources',q);
      box.innerHTML=rows.length
        ?rows.map(c=>{
          const existing=c._Source==='Customer';
          const badge=existing?'<span class="status ready">Customer</span>':'<span class="status">Contact</span>';
          return `<div class="customer-result" onclick='selectQuoteCustomer(${JSON.stringify(c).replace(/'/g,"&#39;")})'>
            <div style="display:flex;justify-content:space-between;gap:8px"><b>${esc(c.Full_Name||'Unnamed')}</b>${badge}</div>
            <span class="muted">${esc(c.Phone_Primary||c.Email||'')}</span>
          </div>`;
        }).join('')
        :'<div class="customer-result muted">No match — enter details manually.</div>';
      box.style.display='block';
    }catch(e){toast(e.message,true)}
  }

  function selectQuoteCustomer(c){
    const existing=c._Source==='Customer'&&c.Customer_ID;
    document.getElementById('selectedQuoteCustomerId').value=existing?c.Customer_ID:'';
    document.getElementById('quoteCustomerName').value=c.Full_Name||'';
    document.getElementById('quoteCustomerPhone').value=c.Phone_Primary||'';
    document.getElementById('quoteCustomerPhoneAlternate').value=c.Phone_Alternate||'';
    document.getElementById('quoteCustomerEmail').value=c.Email||'';
    document.getElementById('quoteCustomerAddress').value=c.Address||'';
    document.getElementById('selectedQuoteCustomer').innerHTML=existing
      ?`Using existing customer <b>${esc(c.Full_Name||'')}</b> · ${esc(c.Customer_ID)}`
      :`Using contact <b>${esc(c.Full_Name||'')}</b>`;
    document.getElementById('selectedQuoteCustomer').style.display='block';
    document.getElementById('quoteCustomerResults').style.display='none';
  }

  function addQuoteItemRow(item={}){
    QUOTE_ITEM_SEQ+=1;
    const row=document.createElement('div');
    row.className='card section quote-item-row';
    row.style.marginBottom='10px';
    row.dataset.row=String(QUOTE_ITEM_SEQ);
    row.dataset.catalogName=item.Product_Name||'';

    row.innerHTML=`
      <div class="section-head"><div><h3>Item ${QUOTE_ITEM_SEQ}</h3><span class="muted" data-role="source-label">${esc(item.Item_Source||'Ad-hoc')}</span></div><button class="btn small" type="button" onclick="removeQuoteItemRow(this)">Remove</button></div>
      <div class="form-grid">
        <div class="full">
          <label class="required">Product / requested item</label>
          <input class="input" data-field="Product_Name" value="${escAttr(item.Product_Name||'')}" placeholder="Search catalog or type any requested item…" oninput="quoteProductChanged(this);debouncedQuoteProductSearch(this)">
          <div class="customer-results" data-role="product-results"></div>
          <input type="hidden" data-field="Catalog_ID" value="${escAttr(item.Catalog_ID||'')}">
          <input type="hidden" data-field="Inventory_ID" value="${escAttr(item.Inventory_ID||'')}">
          <input type="hidden" data-field="Item_Source" value="${escAttr(item.Item_Source||'Ad-hoc')}">
        </div>
        <div><label>SKU</label><input class="input" data-field="SKU" value="${escAttr(item.SKU||'')}"></div>
        <div><label class="required">Quantity</label><input class="input" type="number" min="1" step="1" data-field="Quantity" value="${escAttr(item.Quantity||1)}" oninput="recalcQuote()"></div>
        <div><label>Quoted unit price (₦)</label><input class="input" type="number" min="0" step="1" data-field="Unit_Price" value="${escAttr(item.Unit_Price??'')}" placeholder="Can be blank while sourcing" oninput="recalcQuote()"></div>
        <div><label>Cost estimate (₦)</label><input class="input" type="number" min="0" step="1" data-field="Unit_Cost_Estimate" value="${escAttr(item.Unit_Cost_Estimate??'')}" placeholder="Optional"></div>
        <div><label>IMEI / Serial</label><input class="input" data-field="IMEI_or_Serial" value="${escAttr(item.IMEI_or_Serial||'')}"></div>
        <div class="full"><label style="display:flex;gap:8px;align-items:center;font-weight:700"><input type="checkbox" data-field="Save_to_Catalog"> Save this item to Catalog</label></div>
        <div class="full"><label>Item notes</label><input class="input" data-field="Notes" value="${escAttr(item.Notes||'')}"></div>
        <div class="full" style="text-align:right"><span class="muted">Line:</span> <b class="quote-line-total">${hasDisplayValue(item.Line_Total)?money(item.Line_Total):'Pending price'}</b></div>
      </div>`;

    document.getElementById('quoteItems').appendChild(row);
    recalcQuote();
  }

  function removeQuoteItemRow(button){
    const rows=document.querySelectorAll('.quote-item-row');
    if(rows.length<=1){toast('A quote needs at least one item.',true);return;}
    button.closest('.quote-item-row').remove();
    recalcQuote();
  }

  function debouncedQuoteProductSearch(input){
    clearTimeout(QUOTE_PRODUCT_TIMER);
    QUOTE_PRODUCT_TIMER=setTimeout(()=>searchQuoteProductPicker(input),220);
  }

  async function searchQuoteProductPicker(input){
    const row=input.closest('.quote-item-row');
    const box=row.querySelector('[data-role="product-results"]');
    const q=input.value.trim();
    if(!q){box.style.display='none';return;}

    try{
      const items=await server('searchSalesProducts',q);
      const rowId=row.dataset.row;
      box.innerHTML=items.length
        ?items.map(item=>`<div class="customer-result" onclick='selectQuoteCatalogItem("${escAttr(rowId)}",${JSON.stringify(item).replace(/'/g,"&#39;")})'>
          <b>${esc(item.Product_Name)}</b><br><span class="muted">${esc(item.Catalog_ID)}${item.SKU?' · '+esc(item.SKU):''}${hasDisplayValue(item.Default_Price)?' · '+money(item.Default_Price):''}</span>
        </div>`).join('')+`<div class="customer-result muted" onclick="useQuoteItemAsAdhoc('${escAttr(rowId)}')">Use typed item as ad-hoc</div>`
        :`<div class="customer-result muted" onclick="useQuoteItemAsAdhoc('${escAttr(rowId)}')">No catalog match — keep as ad-hoc</div>`;
      box.style.display='block';
    }catch(e){toast(e.message,true)}
  }

  function selectQuoteCatalogItem(rowId,item){
    const row=[...document.querySelectorAll('.quote-item-row')].find(r=>r.dataset.row===String(rowId));
    if(!row)return;
    setRowField(row,'Product_Name',item.Product_Name||'');
    setRowField(row,'SKU',item.SKU||'');
    setRowField(row,'Catalog_ID',item.Catalog_ID||'');
    setRowField(row,'Item_Source','Catalog');
    row.dataset.catalogName=item.Product_Name||'';
    if(!getRowField(row,'Unit_Price')&&hasDisplayValue(item.Default_Price))setRowField(row,'Unit_Price',item.Default_Price);
    if(!getRowField(row,'Unit_Cost_Estimate')&&hasDisplayValue(item.Default_Cost))setRowField(row,'Unit_Cost_Estimate',item.Default_Cost);
    row.querySelector('[data-role="source-label"]').textContent='Catalog';
    row.querySelector('[data-role="product-results"]').style.display='none';
    recalcQuote();
  }

  function useQuoteItemAsAdhoc(rowId){
    const row=[...document.querySelectorAll('.quote-item-row')].find(r=>r.dataset.row===String(rowId));
    if(!row)return;
    setRowField(row,'Catalog_ID','');
    setRowField(row,'Inventory_ID','');
    setRowField(row,'Item_Source','Ad-hoc');
    row.dataset.catalogName='';
    row.querySelector('[data-role="source-label"]').textContent='Ad-hoc';
    row.querySelector('[data-role="product-results"]').style.display='none';
  }

  function quoteProductChanged(input){
    const row=input.closest('.quote-item-row');
    if(row.dataset.catalogName&&input.value!==row.dataset.catalogName){
      setRowField(row,'Catalog_ID','');
      setRowField(row,'Item_Source','Ad-hoc');
      row.querySelector('[data-role="source-label"]').textContent='Ad-hoc';
    }
  }

  function quoteItemsPayload(){
    return [...document.querySelectorAll('.quote-item-row')].map(row=>{
      const get=(field)=>row.querySelector(`[data-field="${field}"]`)?.value||'';
      const checked=(field)=>!!row.querySelector(`[data-field="${field}"]`)?.checked;
      return {
        Item_Source:get('Item_Source')||'Ad-hoc',
        Catalog_ID:get('Catalog_ID'),
        Inventory_ID:get('Inventory_ID'),
        SKU:get('SKU'),
        Product_Name:get('Product_Name'),
        Quantity:get('Quantity'),
        Unit_Price:get('Unit_Price'),
        Unit_Cost_Estimate:get('Unit_Cost_Estimate'),
        IMEI_or_Serial:get('IMEI_or_Serial'),
        Save_to_Catalog:checked('Save_to_Catalog'),
        Notes:get('Notes'),
      };
    });
  }

  function recalcQuote(){
    let subtotal=0;
    let pending=false;

    document.querySelectorAll('.quote-item-row').forEach(row=>{
      const qty=num(getRowField(row,'Quantity'));
      const raw=getRowField(row,'Unit_Price').trim();
      const view=row.querySelector('.quote-line-total');
      if(raw===''){
        pending=true;
        if(view)view.textContent='Pending price';
      }else{
        const line=qty*num(raw);
        subtotal+=line;
        if(view)view.textContent=money(line);
      }
    });

    const discount=Math.max(0,num(document.getElementById('quoteDiscount')?.value));
    document.getElementById('quotePricingView').textContent=pending?'Pending':'Complete';
    document.getElementById('quoteSubtotalView').textContent=pending?'Pending':money(subtotal);
    document.getElementById('quoteDiscountView').textContent=money(discount);
    document.getElementById('quoteTotalView').textContent=pending?'Pending':money(Math.max(0,subtotal-discount));
  }

  async function submitQuote(e){
    e.preventDefault();
    const data=formObject(e.target);
    data.Items=quoteItemsPayload();
    showLoading(true);
    try{
      CURRENT_QUOTE=await server('saveQuote',data);
      closeModal('quoteModal');
      toast(`Saved ${CURRENT_QUOTE.quote.Quote_ID}`);
      await loadQuotes();
      renderQuoteDetail(CURRENT_QUOTE);
      document.getElementById('quoteDetailModal').classList.add('open');
    }catch(err){toast(err.message,true)}finally{showLoading(false)}
  }

  async function openQuote(id){
    showLoading(true);
    try{
      CURRENT_QUOTE=await server('getQuote',id);
      renderQuoteDetail(CURRENT_QUOTE);
      document.getElementById('quoteDetailModal').classList.add('open');
    }catch(e){toast(e.message,true)}finally{showLoading(false)}
  }

  function renderQuoteDetail(data){
    const q=data.quote||{},c=data.customer||{},items=data.items||[];
    document.getElementById('quoteDetailTitle').textContent=`${q.Quote_ID||'Quote'} · ${c.Full_Name||''}`;

    document.getElementById('quoteDetailBody').innerHTML=`
      <div class="repair-hero">
        <div>
          <div class="detail-list">
            ${detail('Customer',`${esc(c.Full_Name||'')}<br><span class="muted">${esc(c.Phone_Primary||'')}</span>`)}
            ${detail('Status',statusBadge(q.Quote_Status||''))}
            ${detail('Pricing',q.Pricing_Status==='Complete'?'<span class="status ready">Complete</span>':'<span class="status">Pending</span>')}
            ${detail('Valid until',dateOnly(q.Valid_Until)||'—')}
            ${detail('Converted sale',q.Converted_Sales_ID?esc(q.Converted_Sales_ID):'—')}
          </div>
          <div style="margin-top:18px;display:flex;gap:8px;flex-wrap:wrap">
            ${!q.Converted_Sales_ID?'<button class="btn" onclick="editCurrentQuote()">Edit Quote</button>':''}
            ${q.Pricing_Status==='Complete'&&!q.Converted_Sales_ID&&!['Declined','Expired'].includes(q.Quote_Status)?'<button class="btn primary" onclick="convertCurrentQuote()">Convert to Sale</button>':''}
            ${q.Converted_Sales_ID?`<button class="btn primary" onclick="openConvertedSale('${escAttr(q.Converted_Sales_ID)}')">Open Sale</button>`:''}
          </div>
        </div>
        <div class="finance-box">
          <div class="kpi-label" style="color:#bfd0df">Quote value</div>
          <div class="finance-row"><span>Subtotal</span><b>${q.Pricing_Status==='Complete'?money(q.Subtotal):'Pending'}</b></div>
          <div class="finance-row"><span>Discount</span><b>${money(q.Discount_Amount)}</b></div>
          <div class="finance-row big"><span>Total</span><span>${q.Pricing_Status==='Complete'?money(q.Total_Amount):'Pending'}</span></div>
        </div>
      </div>
      <div style="margin-top:24px" class="section-head"><h3>Items</h3></div>
      ${quoteItemsTable(items)}
      ${q.Notes?`<div style="margin-top:18px"><label>Notes</label><div>${nl2br(esc(q.Notes))}</div></div>`:''}`;
  }

  function quoteItemsTable(rows){
    return `<div class="table-wrap"><table><thead><tr><th>Item</th><th>Source</th><th>Qty</th><th>Price</th><th>Cost estimate</th><th>IMEI / Serial</th></tr></thead><tbody>${rows.map(item=>`<tr>
      <td><b>${esc(item.Product_Name)}</b><br><span class="muted">${esc(item.SKU||'')}</span></td>
      <td>${esc(item.Item_Source||'Ad-hoc')}</td>
      <td>${esc(item.Quantity)}</td>
      <td class="money">${item.Price_Status==='Known'?money(item.Unit_Price):'Pending'}</td>
      <td class="money">${hasDisplayValue(item.Unit_Cost_Estimate)?money(item.Unit_Cost_Estimate):'—'}</td>
      <td>${esc(item.IMEI_or_Serial||'')}</td>
    </tr>`).join('')}</tbody></table></div>`;
  }

  function editCurrentQuote(){
    if(!CURRENT_QUOTE)return;
    const q=CURRENT_QUOTE.quote,c=CURRENT_QUOTE.customer||{};
    const form=document.getElementById('quoteForm');
    form.reset();
    document.getElementById('quoteModalTitle').textContent=`Edit ${q.Quote_ID}`;
    document.getElementById('quoteId').value=q.Quote_ID;
    document.getElementById('selectedQuoteCustomerId').value=c.Customer_ID||'';
    document.getElementById('quoteCustomerName').value=c.Full_Name||'';
    document.getElementById('quoteCustomerPhone').value=c.Phone_Primary||'';
    document.getElementById('quoteCustomerPhoneAlternate').value=c.Phone_Alternate||'';
    document.getElementById('quoteCustomerEmail').value=c.Email||'';
    document.getElementById('quoteCustomerAddress').value=c.Address||'';
    document.getElementById('selectedQuoteCustomer').innerHTML=`Using <b>${esc(c.Full_Name||'')}</b> · ${esc(c.Customer_ID||'')}`;
    document.getElementById('selectedQuoteCustomer').style.display='block';
    document.getElementById('quoteStatus').value=q.Quote_Status||'Pricing';
    document.getElementById('quoteValidUntil').value=dateOnly(q.Valid_Until);
    document.getElementById('quoteDiscount').value=q.Discount_Amount||0;
    document.getElementById('quoteNotes').value=q.Notes||'';
    document.getElementById('quoteItems').innerHTML='';
    QUOTE_ITEM_SEQ=0;
    (CURRENT_QUOTE.items||[]).forEach(item=>addQuoteItemRow(item));
    recalcQuote();
    closeModal('quoteDetailModal');
    document.getElementById('quoteModal').classList.add('open');
  }

  async function convertCurrentQuote(){
    if(!CURRENT_QUOTE)return;
    if(!confirm(`Convert ${CURRENT_QUOTE.quote.Quote_ID} into a sale?`))return;
    showLoading(true);
    try{
      CURRENT_SALE=await server('convertQuoteToSale',CURRENT_QUOTE.quote.Quote_ID);
      closeModal('quoteDetailModal');
      toast(`Created ${CURRENT_SALE.order.Sales_ID}`);
      await Promise.all([loadQuotes(),loadSales()]);
      renderSaleDetail(CURRENT_SALE);
      document.getElementById('saleDetailModal').classList.add('open');
    }catch(err){toast(err.message,true)}finally{showLoading(false)}
  }

  function openConvertedSale(id){
    closeModal('quoteDetailModal');
    openSale(id);
  }

'''

if 'function openNewQuote()' not in html:
    html = must_replace(html, client_anchor, phase2_client + client_anchor, "Phase 2 client functions")


# ==========================================================
# 13. Validate before writing
# ==========================================================

required_code = [
    'catalog: "Product_Catalog"',
    'quotes: "Quotes"',
    'FIXXIR_CATALOG_HEADERS',
    'function searchSalesProducts(query)',
    'function updateSaleItemCost(payload)',
    'function saveQuote(payload)',
    'function convertQuoteToSale(quoteId)',
    'Cost_Status_Calc:',
]

required_html = [
    'id="quotesList"',
    'id="quoteModal"',
    'function openNewQuote()',
    'function searchSalesProductPicker(input)',
    'function submitSaleCost(e)',
    'Pending cost',
]

missing = [m for m in required_code if m not in code] + [m for m in required_html if m not in html]
if missing:
    raise SystemExit("ERROR: Phase 2 validation failed. Missing: " + ", ".join(missing))

code_path.write_text(code, encoding="utf-8")
html_path.write_text(html, encoding="utf-8")
PY

echo
echo "======================================================"
echo " Fixxir Sales Phase 2 applied"
echo "======================================================"
echo
echo "Changed:"
echo "  $CODE_FILE"
echo "  $INDEX_FILE"
echo
echo "Backups:"
echo "  ${CODE_FILE}.before-flexible-sales-phase2.bak"
echo "  ${INDEX_FILE}.before-flexible-sales-phase2.bak"
echo
echo "Review:"
echo "  git diff -- $CODE_FILE $INDEX_FILE"
echo
echo "Then deploy:"
echo "  npm run deploy"
echo
echo "What this adds:"
echo "  - Free-form/ad-hoc sale and quote items"
echo "  - Optional Product Catalog"
echo "  - Price-pending quotes"
echo "  - QUO IDs and quote-to-sale conversion"
echo "  - Unknown/estimated cost tracking"
echo "  - Profit stays Pending until actual costs are known"
echo "  - Late actual-cost update on sale items"
echo "  - Optional Catalog_ID / Inventory_ID linkage fields"
echo
echo "What it intentionally does NOT do yet:"
echo "  - Purchase batches / landed-cost allocation"
echo "  - Inventory stock deduction"
echo "  - Automatic IMEI availability control"
echo
