#!/usr/bin/env bash
set -euo pipefail

# Fixxir Sales Phase 1 patch
# - Removes government ID Number from repair/customer intake
# - Enables Sales navigation
# - Adds sales orders, multiple line items, customer/contact picker
# - Adds initial payment + later payment posting to Finance_Ledger
# - Adds sales list/detail/profit/balance views
# - Does NOT deduct Inventory yet (that is the next sales/inventory patch)

CODE_FILE="${1:-Code.js}"
INDEX_FILE="${2:-Index.html}"

for f in "$CODE_FILE" "$INDEX_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: $f not found."
    echo "Run this script from the Fixxir repository root."
    exit 1
  fi
done

if grep -q 'function createSale(payload)' "$CODE_FILE" && \
   grep -q 'function renderSalesPage()' "$INDEX_FILE"; then
  echo "Sales Phase 1 is already installed."
  exit 0
fi

cp "$CODE_FILE" "${CODE_FILE}.before-sales-phase1.bak"
cp "$INDEX_FILE" "${INDEX_FILE}.before-sales-phase1.bak"

python3 - "$CODE_FILE" "$INDEX_FILE" <<'PY'
from pathlib import Path
import sys

code_path = Path(sys.argv[1])
html_path = Path(sys.argv[2])

code = code_path.read_text(encoding="utf-8")
html = html_path.read_text(encoding="utf-8")

def must_replace(text, old, new, label):
    if old not in text:
        raise SystemExit(f"ERROR: Could not find expected anchor for {label}. No files were written.")
    return text.replace(old, new, 1)

# ==========================================================
# 1. Remove government ID Number from repair/customer intake
# ==========================================================

html = html.replace(
    '          <div><label>ID number</label><input class="input" name="Customer_ID_Number"></div>\n',
    '',
)

code = code.replace('        c.ID_Number,\n', '')
code = code.replace('    ID_Type: clean_(payload.ID_Type),\n', '')
code = code.replace('    ID_Number: clean_(payload.ID_Number),\n', '')
code = code.replace('      ID_Type: payload.Customer_ID_Type,\n', '')
code = code.replace('      ID_Number: payload.Customer_ID_Number,\n', '')

# ==========================================================
# 2. Sales schema constants
# ==========================================================

constants_anchor = '''const FIXXIR_CONTACT_HEADERS = Object.freeze([
  "Contact_ID",
  "Full_Name",
  "Phone_Primary",
  "Phone_Primary_Normalized",
  "Phone_Alternate",
  "Phone_Alternate_Normalized",
  "All_Phones",
  "Email",
  "All_Emails",
  "Company",
  "Job_Title",
  "Address",
  "Source",
  "Search_Key",
]);
'''

sales_constants = constants_anchor + r'''

const FIXXIR_SALES_ORDER_HEADERS = Object.freeze([
  "Sales_ID",
  "Date",
  "Customer_ID",
  "Sales_Status",
  "Subtotal",
  "Discount_Amount",
  "Total_Amount",
  "Amount_Paid",
  "Balance",
  "Payment_Status",
  "Payment_Method",
  "Created_By",
  "Last_Updated",
  "Notes",
]);

const FIXXIR_SALES_ITEM_HEADERS = Object.freeze([
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

if 'FIXXIR_SALES_ORDER_HEADERS' not in code:
    code = must_replace(
        code,
        constants_anchor,
        sales_constants,
        "sales schema constants",
    )

# ==========================================================
# 3. Ensure sales sheet columns during initialization
# ==========================================================

init_anchor = '''  ensureContactsSheet_(ss);

  const requiredSheets = Object.values(FIXXIR.sheets);
'''

init_replacement = '''  ensureContactsSheet_(ss);
  ensureSalesSheets_(ss);

  const requiredSheets = Object.values(FIXXIR.sheets);
'''

if 'ensureSalesSheets_(ss);' not in code:
    code = must_replace(code, init_anchor, init_replacement, "sales sheet initialization")

# ==========================================================
# 4. Sales backend API
# ==========================================================

backend_anchor = 'function postFinance(payload) {\n'

sales_backend = r'''/* ---------------- Sales ---------------- */

function getSalesPageData(filters) {
  assertAuthorized_();
  ensureSalesSheets_(getSpreadsheet_());

  const sales = buildSalesRows_(filters || {});
  const allRows = buildSalesRows_({});

  const active = allRows.filter((row) => row.Sales_Status !== "Cancelled");

  return {
    sales,
    summary: {
      orders: active.length,
      totalSales: active.reduce((sum, row) => sum + number_(row.Total_Amount), 0),
      amountPaid: active.reduce((sum, row) => sum + number_(row.Amount_Paid_Calc), 0),
      outstanding: active.reduce((sum, row) => sum + number_(row.Balance_Calc), 0),
      grossProfit: active.reduce((sum, row) => sum + number_(row.Gross_Profit_Calc), 0),
    },
  };
}

function listSales(filters) {
  assertAuthorized_();
  ensureSalesSheets_(getSpreadsheet_());
  return buildSalesRows_(filters || {});
}

function buildSalesRows_(filters) {
  const orders = getRecords_(FIXXIR.sheets.salesOrders);
  const items = getRecords_(FIXXIR.sheets.salesItems);
  const customers = objectMap_(getRecords_(FIXXIR.sheets.customers), "Customer_ID");
  const financeMap = buildSalesFinanceMap_();

  const itemMap = {};
  items.forEach((item) => {
    const id = item.Sales_ID;
    if (!id) return;

    if (!itemMap[id]) {
      itemMap[id] = {
        itemCount: 0,
        quantity: 0,
        costTotal: 0,
        names: [],
        search: [],
      };
    }

    const bucket = itemMap[id];
    bucket.itemCount += 1;
    bucket.quantity += number_(item.Quantity);
    bucket.costTotal += number_(item.Cost_Total) ||
      number_(item.Unit_Cost) * number_(item.Quantity);

    const name = clean_(item.Product_Name);
    if (name && !bucket.names.includes(name)) bucket.names.push(name);

    [
      item.Product_Name,
      item.SKU,
      item.Product_ID,
      item.IMEI_or_Serial,
    ].forEach((value) => {
      if (value) bucket.search.push(String(value));
    });
  });

  let rows = orders.map((order) => {
    const customer = customers[order.Customer_ID] || {};
    const finance = financeMap[order.Sales_ID] || { credits: 0, debits: 0 };
    const itemSummary = itemMap[order.Sales_ID] || {
      itemCount: 0,
      quantity: 0,
      costTotal: 0,
      names: [],
      search: [],
    };

    const total = number_(order.Total_Amount);
    const paid = finance.credits;
    const balance = Math.max(0, total - paid);

    return Object.assign({}, order, {
      Customer_Name: customer.Full_Name || "",
      Customer_Phone: customer.Phone_Primary || "",
      Item_Count_Calc: itemSummary.itemCount,
      Quantity_Calc: itemSummary.quantity,
      Item_Summary: itemSummary.names.slice(0, 3).join(", "),
      Item_Search: itemSummary.search.join(" "),
      Amount_Paid_Calc: paid,
      Balance_Calc: balance,
      Payment_Status_Calc: salePaymentStatus_(total, paid),
      Cost_Total_Calc: itemSummary.costTotal,
      Gross_Profit_Calc: total - itemSummary.costTotal,
    });
  });

  const q = clean_(filters.q).toLowerCase();
  const status = clean_(filters.status);
  const paymentStatus = clean_(filters.paymentStatus);

  if (q) {
    rows = rows.filter((row) =>
      [
        row.Sales_ID,
        row.Customer_Name,
        row.Customer_Phone,
        row.Item_Summary,
        row.Item_Search,
      ].some((value) =>
        String(value || "").toLowerCase().includes(q),
      ),
    );
  }

  if (status) rows = rows.filter((row) => row.Sales_Status === status);
  if (paymentStatus) {
    rows = rows.filter((row) => row.Payment_Status_Calc === paymentStatus);
  }

  rows.sort((a, b) =>
    String(b.Date || "").localeCompare(String(a.Date || "")),
  );

  return rows.slice(0, 300);
}

function getSale(salesId) {
  assertAuthorized_();
  ensureSalesSheets_(getSpreadsheet_());

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
    .sort((a, b) => String(b.Date || "").localeCompare(String(a.Date || "")));

  const paid = transactions
    .filter((txn) => txn.Transaction_Type === "Credit")
    .reduce((sum, txn) => sum + number_(txn.Amount), 0);

  const total = number_(order.Total_Amount);
  const costTotal = items.reduce(
    (sum, item) =>
      sum +
      (number_(item.Cost_Total) ||
        number_(item.Unit_Cost) * number_(item.Quantity)),
    0,
  );

  return {
    order,
    customer,
    items,
    transactions,
    summary: {
      subtotal: number_(order.Subtotal),
      discount: number_(order.Discount_Amount),
      total,
      paid,
      balance: Math.max(0, total - paid),
      paymentStatus: salePaymentStatus_(total, paid),
      costTotal,
      grossProfit: total - costTotal,
    },
  };
}

function createSale(payload) {
  assertAuthorized_();
  ensureSalesSheets_(getSpreadsheet_());

  payload = payload || {};

  let items = payload.Items || [];
  if (typeof items === "string") {
    try {
      items = JSON.parse(items);
    } catch (error) {
      throw new Error("Sale items could not be read.");
    }
  }

  if (!Array.isArray(items) || !items.length) {
    throw new Error("Add at least one item to the sale.");
  }

  const cleanItems = items.map((item, index) => {
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

  const subtotal = cleanItems.reduce(
    (sum, item) => sum + number_(item.Line_Total),
    0,
  );

  const discount = number_(payload.Discount_Amount);
  if (discount < 0) throw new Error("Discount cannot be negative.");
  if (discount > subtotal) throw new Error("Discount cannot exceed subtotal.");

  const total = subtotal - discount;
  const initialPayment = number_(payload.Initial_Payment);

  if (initialPayment < 0) {
    throw new Error("Initial payment cannot be negative.");
  }
  if (initialPayment > total) {
    throw new Error("Initial payment cannot exceed the sale total.");
  }
  if (initialPayment > 0 && !clean_(payload.Payment_Method)) {
    throw new Error("Select a payment method for the initial payment.");
  }

  const salesId = generateId_(FIXXIR.sheets.salesOrders);
  const now = new Date();

  appendRecord_(FIXXIR.sheets.salesOrders, {
    Sales_ID: salesId,
    Date: parseDate_(payload.Date) || now,
    Customer_ID: customerId,
    Sales_Status: clean_(payload.Sales_Status) || "Completed",
    Subtotal: subtotal,
    Discount_Amount: discount,
    Total_Amount: total,
    Amount_Paid: initialPayment,
    Balance: Math.max(0, total - initialPayment),
    Payment_Status: salePaymentStatus_(total, initialPayment),
    Payment_Method: clean_(payload.Payment_Method),
    Created_By: currentUser_(),
    Last_Updated: now,
    Notes: clean_(payload.Notes),
  });

  cleanItems.forEach((item) => {
    appendRecord_(
      FIXXIR.sheets.salesItems,
      Object.assign(
        {
          Sales_Item_ID: generateId_(FIXXIR.sheets.salesItems),
          Sales_ID: salesId,
        },
        item,
      ),
    );
  });

  if (initialPayment > 0) {
    postFinance({
      Transaction_Type: "Credit",
      Category: "Sales Revenue",
      Amount: initialPayment,
      Payment_Method: payload.Payment_Method,
      Account: payload.Account || "Operating",
      Sales_ID: salesId,
      Customer_ID: customerId,
      Reference_Type: "Sale",
      Reference_ID: salesId,
      Description: "Initial payment for " + salesId,
      Receipt_Reference: payload.Receipt_Reference,
      Notes: payload.Payment_Notes,
    });
  }

  syncSalePaymentFields_(salesId);
  return getSale(salesId);
}

function postSalePayment(payload) {
  assertAuthorized_();
  payload = payload || {};

  const salesId = clean_(payload.Sales_ID);
  if (!salesId) throw new Error("Sales_ID is required.");

  const sale = getSale(salesId);
  const amount = number_(payload.Amount);

  if (!(amount > 0)) throw new Error("Payment amount must be greater than zero.");
  if (amount > sale.summary.balance) {
    throw new Error("Payment cannot exceed the outstanding sale balance.");
  }

  postFinance({
    Transaction_Type: "Credit",
    Category: "Sales Revenue",
    Amount: amount,
    Payment_Method: payload.Payment_Method,
    Account: payload.Account || "Operating",
    Sales_ID: salesId,
    Customer_ID: sale.order.Customer_ID,
    Reference_Type: "Sale",
    Reference_ID: salesId,
    Description: clean_(payload.Description) || "Payment for " + salesId,
    Receipt_Reference: payload.Receipt_Reference,
    Notes: payload.Notes,
  });

  syncSalePaymentFields_(salesId);
  return getSale(salesId);
}

function syncSalePaymentFields_(salesId) {
  const sale = getSale(salesId);

  updateRecordById_(FIXXIR.sheets.salesOrders, "Sales_ID", salesId, {
    Amount_Paid: sale.summary.paid,
    Balance: sale.summary.balance,
    Payment_Status: sale.summary.paymentStatus,
    Last_Updated: new Date(),
  });
}

function buildSalesFinanceMap_(financeRows) {
  const rows = financeRows || getRecords_(FIXXIR.sheets.finance);
  const map = {};

  rows.forEach((txn) => {
    const id =
      txn.Sales_ID ||
      (txn.Reference_Type === "Sale" ? txn.Reference_ID : "");

    if (!id) return;
    if (!map[id]) map[id] = { credits: 0, debits: 0 };

    if (txn.Transaction_Type === "Credit") {
      map[id].credits += number_(txn.Amount);
    }
    if (txn.Transaction_Type === "Debit") {
      map[id].debits += number_(txn.Amount);
    }
  });

  return map;
}

function salePaymentStatus_(total, paid) {
  total = number_(total);
  paid = number_(paid);

  if (total <= 0) return "Paid";
  if (paid >= total) return "Paid";
  if (paid > 0) return "Part Paid";
  return "Unpaid";
}

function ensureSalesSheets_(ss) {
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

function ensureSheetColumns_(ss, sheetName, requiredHeaders) {
  let sh = ss.getSheetByName(sheetName);

  if (!sh) {
    sh = ss.insertSheet(sheetName);
  }

  const lastCol = sh.getLastColumn();

  if (!lastCol) {
    sh.getRange(1, 1, 1, requiredHeaders.length).setValues([requiredHeaders]);
    sh.setFrozenRows(1);
    return sh;
  }

  const existingHeaders = sh
    .getRange(1, 1, 1, lastCol)
    .getValues()[0]
    .map((header) => String(header || "").trim());

  const missingHeaders = requiredHeaders.filter(
    (header) => !existingHeaders.includes(header),
  );

  if (missingHeaders.length) {
    sh.getRange(1, lastCol + 1, 1, missingHeaders.length).setValues([
      missingHeaders,
    ]);
  }

  sh.setFrozenRows(1);
  return sh;
}

'''

if 'function createSale(payload)' not in code:
    code = must_replace(code, backend_anchor, sales_backend + backend_anchor, "sales backend")

# Validate Sales_ID in finance posts too.
finance_validation_anchor = '''  if (repairId && !findById_(FIXXIR.sheets.repairs, "Repair_ID", repairId)) {
    throw new Error("Repair not found: " + repairId);
  }

  const txnId = generateId_(FIXXIR.sheets.finance);
'''

finance_validation_replacement = '''  if (repairId && !findById_(FIXXIR.sheets.repairs, "Repair_ID", repairId)) {
    throw new Error("Repair not found: " + repairId);
  }

  if (salesId && !findById_(FIXXIR.sheets.salesOrders, "Sales_ID", salesId)) {
    throw new Error("Sale not found: " + salesId);
  }

  const txnId = generateId_(FIXXIR.sheets.finance);
'''

if 'throw new Error("Sale not found: " + salesId);' not in code:
    code = must_replace(
        code,
        finance_validation_anchor,
        finance_validation_replacement,
        "sales finance validation",
    )

# ==========================================================
# 5. Enable Sales navigation
# ==========================================================

nav_old = '      <button class="disabled" title="Next build phase">▣ Sales — next</button>\n'
nav_new = '      <button data-page="sales" onclick="navigate(\'sales\',this)">▣ Sales</button>\n'

if 'data-page="sales"' not in html:
    html = must_replace(html, nav_old, nav_new, "Sales navigation")

navigate_anchor = '''    if (page === 'customers') renderCustomersPage();
    if (page === 'finance') renderFinancePage();
'''

navigate_replacement = '''    if (page === 'customers') renderCustomersPage();
    if (page === 'sales') renderSalesPage();
    if (page === 'finance') renderFinancePage();
'''

if "if (page === 'sales') renderSalesPage();" not in html:
    html = must_replace(html, navigate_anchor, navigate_replacement, "Sales route")

# ==========================================================
# 6. Sales modals
# ==========================================================

modal_anchor = '<div class="modal" id="financeModal">\n'

sales_modals = r'''<div class="modal" id="saleModal">
  <div class="modal-box" style="width:min(1100px,100%)">
    <div class="modal-head"><h3>New Sale</h3><button class="close" onclick="closeModal('saleModal')">×</button></div>
    <form id="saleForm" onsubmit="submitSale(event)">
      <div class="modal-body">
        <div class="section-head"><h3>Customer</h3><span class="muted" style="font-size:12px">Search customers or imported contacts</span></div>
        <div class="form-grid">
          <div class="full">
            <label>Find customer/contact</label>
            <input class="input" id="saleCustomerSearch" placeholder="Name, phone, customer ID…" oninput="debouncedSaleCustomerSearch(this.value)">
            <div class="customer-results" id="saleCustomerResults"></div>
            <div class="selected-customer" id="selectedSaleCustomer"></div>
            <input type="hidden" name="Customer_ID" id="selectedSaleCustomerId">
            <input type="hidden" name="Customer_Phone_Alternate" id="saleCustomerPhoneAlternate">
            <input type="hidden" name="Customer_Address" id="saleCustomerAddress">
          </div>
          <div><label class="required">Customer name</label><input class="input" name="Customer_Name" id="saleCustomerName" required></div>
          <div><label class="required">Phone</label><input class="input" name="Customer_Phone" id="saleCustomerPhone" required></div>
          <div><label>Email</label><input class="input" name="Customer_Email" id="saleCustomerEmail"></div>
          <div><label>Sale status</label><select class="select" name="Sales_Status"><option selected>Completed</option><option>Draft</option><option>Cancelled</option></select></div>
        </div>

        <div class="section-head" style="margin-top:24px">
          <div><h3>Items</h3><div class="muted" style="font-size:12px;margin-top:4px">For phones/laptops with an IMEI or serial, enter one device per row.</div></div>
          <button type="button" class="btn small" onclick="addSaleItemRow()">+ Add item</button>
        </div>
        <div id="saleItems"></div>

        <div class="form-grid" style="margin-top:20px">
          <div><label>Discount (₦)</label><input class="input" id="saleDiscount" type="number" min="0" step="1" name="Discount_Amount" value="0" oninput="recalcSale()"></div>
          <div><label>Initial payment (₦)</label><input class="input" id="saleInitialPayment" type="number" min="0" step="1" name="Initial_Payment" value="0" oninput="recalcSale()"></div>
          <div><label>Payment method</label><select class="select" name="Payment_Method" id="salePaymentMethod"></select></div>
          <div><label>Receipt / bank reference</label><input class="input" name="Receipt_Reference"></div>
          <div class="full">
            <div class="finance-box">
              <div class="finance-row"><span>Subtotal</span><b id="saleSubtotalView">₦0</b></div>
              <div class="finance-row"><span>Discount</span><b id="saleDiscountView">₦0</b></div>
              <div class="finance-row big"><span>Total</span><span id="saleTotalView">₦0</span></div>
              <div class="finance-row"><span>Initial payment</span><b id="salePaidView">₦0</b></div>
              <div class="finance-row"><span>Balance</span><b id="saleBalanceView">₦0</b></div>
            </div>
          </div>
          <div class="full"><label>Notes</label><textarea class="textarea" name="Notes"></textarea></div>
        </div>
      </div>
      <div class="modal-foot"><button type="button" class="btn" onclick="closeModal('saleModal')">Cancel</button><button class="btn primary" type="submit">Create sale</button></div>
    </form>
  </div>
</div>

<div class="modal" id="saleDetailModal">
  <div class="modal-box" style="width:min(1100px,100%)">
    <div class="modal-head"><h3 id="saleDetailTitle">Sale</h3><button class="close" onclick="closeModal('saleDetailModal')">×</button></div>
    <div class="modal-body" id="saleDetailBody"></div>
  </div>
</div>

<div class="modal" id="salePaymentModal">
  <div class="modal-box" style="width:min(650px,100%)">
    <div class="modal-head"><h3 id="salePaymentTitle">Record sale payment</h3><button class="close" onclick="closeModal('salePaymentModal')">×</button></div>
    <form id="salePaymentForm" onsubmit="submitSalePayment(event)">
      <div class="modal-body">
        <input type="hidden" name="Sales_ID" id="salePaymentSalesId">
        <div class="form-grid">
          <div><label class="required">Amount (₦)</label><input class="input" id="salePaymentAmount" type="number" min="1" step="1" name="Amount" required></div>
          <div><label class="required">Payment method</label><select class="select" name="Payment_Method" id="salePaymentMethodDetail" required></select></div>
          <div><label>Account</label><input class="input" name="Account" value="Operating"></div>
          <div><label>Receipt / bank reference</label><input class="input" name="Receipt_Reference"></div>
          <div class="full"><label>Description</label><input class="input" name="Description"></div>
          <div class="full"><label>Notes</label><textarea class="textarea" name="Notes"></textarea></div>
        </div>
      </div>
      <div class="modal-foot"><button type="button" class="btn" onclick="closeModal('salePaymentModal')">Cancel</button><button class="btn primary" type="submit">Record payment</button></div>
    </form>
  </div>
</div>

'''

if 'id="saleModal"' not in html:
    html = must_replace(html, modal_anchor, sales_modals + modal_anchor, "sales modals")

# ==========================================================
# 7. Sales JS globals + static selects
# ==========================================================

globals_anchor = '''  let CUSTOMER_TIMER = null;
  let CURRENT_REPAIR = null;
'''

globals_replacement = '''  let CUSTOMER_TIMER = null;
  let CURRENT_REPAIR = null;
  let CURRENT_SALE = null;
  let SALE_TIMER = null;
  let SALE_CUSTOMER_TIMER = null;
  let SALE_ITEM_SEQ = 0;
'''

if 'let CURRENT_SALE = null;' not in html:
    html = must_replace(html, globals_anchor, globals_replacement, "sales globals")

select_anchor = '''    fillSelect('financePaymentMethod', BOOT.settings.Payment_Method || [], 'Select method');
    fillSelect('financeCategory', BOOT.settings.Finance_Category || [], 'Select category');
'''

select_replacement = '''    fillSelect('financePaymentMethod', BOOT.settings.Payment_Method || [], 'Select method');
    fillSelect('financeCategory', BOOT.settings.Finance_Category || [], 'Select category');
    fillSelect('salePaymentMethod', BOOT.settings.Payment_Method || [], 'Select method');
    fillSelect('salePaymentMethodDetail', BOOT.settings.Payment_Method || [], 'Select method');
'''

if "fillSelect('salePaymentMethod'" not in html:
    html = must_replace(html, select_anchor, select_replacement, "sales payment method selects")

# ==========================================================
# 8. Sales page/client logic
# ==========================================================

sales_ui_anchor = '  function renderFinancePage() {\n'

sales_ui = r'''  async function renderSalesPage(){
    document.getElementById('content').innerHTML=`
      <div class="toolbar">
        <div><h2>Sales</h2><div class="muted" style="margin-top:5px">Phones, laptops, accessories and other product sales.</div></div>
        <div class="actions"><button class="btn primary" onclick="openNewSale()">+ New Sale</button></div>
      </div>
      <div class="grid kpis" id="salesKpis">
        ${kpi('Orders','—','Sales orders')}
        ${kpi('Sales value','—','Completed/non-cancelled sales')}
        ${kpi('Outstanding','—','Customer balances')}
        ${kpi('Gross profit','—','Sales less recorded item cost')}
      </div>
      <div class="filters" style="margin-bottom:14px">
        <input class="input" id="salesQ" placeholder="Search sale, customer, IMEI, serial, SKU…" oninput="debouncedSalesLoad()">
        <select class="select" id="salesStatus" onchange="loadSales()">
          <option value="">All statuses</option>
          <option>Completed</option><option>Draft</option><option>Cancelled</option>
        </select>
        <select class="select" id="salesPaymentStatus" onchange="loadSales()">
          <option value="">All payment statuses</option>
          <option>Paid</option><option>Part Paid</option><option>Unpaid</option>
        </select>
      </div>
      <div class="card section" id="salesList"><div class="empty">Loading sales…</div></div>`;

    await loadSales();
  }

  function debouncedSalesLoad(){
    clearTimeout(SALE_TIMER);
    SALE_TIMER=setTimeout(loadSales,300);
  }

  async function loadSales(){
    try{
      const q=document.getElementById('salesQ')?.value||'';
      const status=document.getElementById('salesStatus')?.value||'';
      const paymentStatus=document.getElementById('salesPaymentStatus')?.value||'';

      const data=await server('getSalesPageData',{q,status,paymentStatus});
      const s=data.summary||{};

      const kpis=document.getElementById('salesKpis');
      if(kpis){
        kpis.innerHTML=`
          ${kpi('Orders',s.orders||0,'Sales orders')}
          ${kpi('Sales value',money(s.totalSales),'Completed/non-cancelled sales')}
          ${kpi('Outstanding',money(s.outstanding),'Customer balances')}
          ${kpi('Gross profit',money(s.grossProfit),'Sales less recorded item cost')}`;
      }

      const box=document.getElementById('salesList');
      const rows=data.sales||[];

      if(!rows.length){
        box.innerHTML='<div class="empty">No matching sales.</div>';
        return;
      }

      box.innerHTML=`<div class="table-wrap"><table>
        <thead><tr><th>Sale</th><th>Customer</th><th>Items</th><th>Status</th><th>Total</th><th>Paid</th><th>Balance</th><th>Payment</th></tr></thead>
        <tbody>${rows.map(row=>`
          <tr class="clickable" onclick="openSale('${escAttr(row.Sales_ID)}')">
            <td><b>${esc(row.Sales_ID)}</b><br><span class="muted">${dateOnly(row.Date)}</span></td>
            <td>${esc(row.Customer_Name)}<br><span class="muted">${esc(row.Customer_Phone)}</span></td>
            <td>${esc(row.Item_Summary||`${row.Item_Count_Calc||0} item(s)`)}</td>
            <td>${statusBadge(row.Sales_Status)}</td>
            <td class="money">${money(row.Total_Amount)}</td>
            <td class="money">${money(row.Amount_Paid_Calc)}</td>
            <td class="money">${money(row.Balance_Calc)}</td>
            <td>${salePaymentBadge(row.Payment_Status_Calc)}</td>
          </tr>`).join('')}</tbody></table></div>`;
    }catch(e){
      toast(e.message,true);
    }
  }

  function openNewSale(){
    const form=document.getElementById('saleForm');
    form.reset();

    document.getElementById('selectedSaleCustomerId').value='';
    document.getElementById('saleCustomerPhoneAlternate').value='';
    document.getElementById('saleCustomerAddress').value='';
    document.getElementById('selectedSaleCustomer').style.display='none';
    document.getElementById('saleCustomerResults').style.display='none';

    document.getElementById('saleItems').innerHTML='';
    SALE_ITEM_SEQ=0;
    addSaleItemRow();

    fillSelect('salePaymentMethod',BOOT.settings.Payment_Method||[],'Select method');
    recalcSale();
    document.getElementById('saleModal').classList.add('open');
  }

  function debouncedSaleCustomerSearch(q){
    clearTimeout(SALE_CUSTOMER_TIMER);
    SALE_CUSTOMER_TIMER=setTimeout(()=>searchSaleCustomerPicker(q),280);
  }

  async function searchSaleCustomerPicker(q){
    const box=document.getElementById('saleCustomerResults');
    if(!q.trim()){box.style.display='none';return;}

    try{
      const rows=await server('searchCustomerSources',q);

      box.innerHTML=rows.length
        ? rows.map(c=>{
            const isCustomer=c._Source==='Customer';
            const sourceId=isCustomer?c.Customer_ID:(c.Contact_ID||'Contact');
            const badge=isCustomer
              ? '<span class="status ready">Customer</span>'
              : '<span class="status">Contact</span>';

            return `<div class="customer-result" onclick='selectSaleCustomer(${JSON.stringify(c).replace(/'/g,"&#39;")})'>
              <div style="display:flex;align-items:center;justify-content:space-between;gap:8px">
                <b>${esc(c.Full_Name||'Unnamed contact')}</b>${badge}
              </div>
              <span class="muted">${esc(sourceId)} · ${esc(c.Phone_Primary||c.Email||'No phone')}</span>
            </div>`;
          }).join('')
        : '<div class="customer-result muted">No customer/contact found — enter details manually.</div>';

      box.style.display='block';
    }catch(e){toast(e.message,true)}
  }

  function selectSaleCustomer(c){
    const existing=c._Source==='Customer'&&c.Customer_ID;

    document.getElementById('selectedSaleCustomerId').value=existing?c.Customer_ID:'';
    document.getElementById('saleCustomerName').value=c.Full_Name||'';
    document.getElementById('saleCustomerPhone').value=c.Phone_Primary||'';
    document.getElementById('saleCustomerPhoneAlternate').value=c.Phone_Alternate||'';
    document.getElementById('saleCustomerEmail').value=c.Email||'';
    document.getElementById('saleCustomerAddress').value=c.Address||'';

    document.getElementById('selectedSaleCustomer').innerHTML=existing
      ? `Using existing customer <b>${esc(c.Full_Name||'')}</b> · ${esc(c.Customer_ID)}`
      : `Using contact <b>${esc(c.Full_Name||'')}</b><br><span class="muted">A customer record will be created with this sale.</span>`;

    document.getElementById('selectedSaleCustomer').style.display='block';
    document.getElementById('saleCustomerResults').style.display='none';
  }

  function addSaleItemRow(item={}){
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

  function removeSaleItemRow(button){
    const rows=document.querySelectorAll('.sale-item-row');
    if(rows.length<=1){
      toast('A sale needs at least one item.',true);
      return;
    }
    button.closest('.sale-item-row').remove();
    recalcSale();
  }

  function saleItemsPayload(){
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

  function recalcSale(){
    let subtotal=0;

    document.querySelectorAll('.sale-item-row').forEach(row=>{
      const qty=num(row.querySelector('[data-field="Quantity"]')?.value);
      const price=num(row.querySelector('[data-field="Unit_Price"]')?.value);
      const line=qty*price;
      subtotal+=line;

      const view=row.querySelector('.sale-line-total');
      if(view)view.textContent=money(line);
    });

    const discount=Math.max(0,num(document.getElementById('saleDiscount')?.value));
    const total=Math.max(0,subtotal-discount);
    const paid=Math.max(0,num(document.getElementById('saleInitialPayment')?.value));
    const balance=Math.max(0,total-paid);

    if(document.getElementById('saleSubtotalView'))document.getElementById('saleSubtotalView').textContent=money(subtotal);
    if(document.getElementById('saleDiscountView'))document.getElementById('saleDiscountView').textContent=money(discount);
    if(document.getElementById('saleTotalView'))document.getElementById('saleTotalView').textContent=money(total);
    if(document.getElementById('salePaidView'))document.getElementById('salePaidView').textContent=money(paid);
    if(document.getElementById('saleBalanceView'))document.getElementById('saleBalanceView').textContent=money(balance);
  }

  async function submitSale(e){
    e.preventDefault();

    const data=formObject(e.target);
    data.Items=saleItemsPayload();

    if(!data.Items.length){
      toast('Add at least one item.',true);
      return;
    }

    const payment=num(data.Initial_Payment);
    if(payment>0&&!data.Payment_Method){
      toast('Select a payment method for the initial payment.',true);
      return;
    }

    showLoading(true);
    try{
      CURRENT_SALE=await server('createSale',data);
      closeModal('saleModal');
      toast(`Created ${CURRENT_SALE.order.Sales_ID}`);

      if(CURRENT_PAGE==='sales')await loadSales();

      renderSaleDetail(CURRENT_SALE);
      document.getElementById('saleDetailModal').classList.add('open');

      BOOT.dashboard=await server('refreshDashboard');
    }catch(err){
      toast(err.message,true);
    }finally{
      showLoading(false);
    }
  }

  async function openSale(id){
    showLoading(true);
    try{
      CURRENT_SALE=await server('getSale',id);
      renderSaleDetail(CURRENT_SALE);
      document.getElementById('saleDetailModal').classList.add('open');
    }catch(e){
      toast(e.message,true);
    }finally{
      showLoading(false);
    }
  }

  function renderSaleDetail(data){
    const order=data.order||{};
    const customer=data.customer||{};
    const summary=data.summary||{};
    const items=data.items||[];

    document.getElementById('saleDetailTitle').textContent=
      `${order.Sales_ID||'Sale'} · ${customer.Full_Name||''}`;

    document.getElementById('saleDetailBody').innerHTML=`
      <div class="repair-hero">
        <div>
          <div class="detail-list">
            ${detail('Customer',`${esc(customer.Full_Name||'')}<br><span class="muted">${esc(customer.Phone_Primary||'')}</span>`)}
            ${detail('Status',statusBadge(order.Sales_Status||''))}
            ${detail('Date',dateOnly(order.Date)||'—')}
            ${detail('Payment',salePaymentBadge(summary.paymentStatus))}
            ${detail('Items',String(items.length))}
            ${detail('Created by',esc(order.Created_By||'—'))}
          </div>
          <div style="margin-top:18px;display:flex;gap:8px;flex-wrap:wrap">
            ${summary.balance>0?'<button class="btn primary" onclick="openSalePayment()">+ Record Payment</button>':''}
          </div>
        </div>
        <div class="finance-box">
          <div class="kpi-label" style="color:#bfd0df">Sale economics</div>
          <div class="finance-row"><span>Subtotal</span><b>${money(summary.subtotal)}</b></div>
          <div class="finance-row"><span>Discount</span><b>${money(summary.discount)}</b></div>
          <div class="finance-row big"><span>Total</span><span>${money(summary.total)}</span></div>
          <div class="finance-row"><span>Paid</span><b>${money(summary.paid)}</b></div>
          <div class="finance-row"><span>Balance</span><b>${money(summary.balance)}</b></div>
          <div class="finance-row"><span>Recorded cost</span><b>${money(summary.costTotal)}</b></div>
          <div class="finance-row big"><span>Gross profit</span><span>${money(summary.grossProfit)}</span></div>
        </div>
      </div>

      <div style="margin-top:24px" class="section-head"><h3>Items</h3></div>
      ${saleItemsTable(items)}

      <div style="margin-top:24px" class="section-head"><h3>Payments</h3></div>
      ${transactionTable(data.transactions||[])}`;

  }

  function saleItemsTable(rows){
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

  function salePaymentBadge(status){
    const cls=status==='Paid'?' ready':'';
    return `<span class="status${cls}">${esc(status||'Unpaid')}</span>`;
  }

  function openSalePayment(){
    if(!CURRENT_SALE)return;

    const form=document.getElementById('salePaymentForm');
    form.reset();

    document.getElementById('salePaymentSalesId').value=CURRENT_SALE.order.Sales_ID;
    document.getElementById('salePaymentTitle').textContent=`Record payment · ${CURRENT_SALE.order.Sales_ID}`;
    document.getElementById('salePaymentAmount').max=String(CURRENT_SALE.summary.balance||'');
    fillSelect('salePaymentMethodDetail',BOOT.settings.Payment_Method||[],'Select method');

    document.getElementById('salePaymentModal').classList.add('open');
  }

  async function submitSalePayment(e){
    e.preventDefault();

    const data=formObject(e.target);
    showLoading(true);

    try{
      CURRENT_SALE=await server('postSalePayment',data);
      closeModal('salePaymentModal');
      toast('Sale payment recorded');
      renderSaleDetail(CURRENT_SALE);

      if(CURRENT_PAGE==='sales')await loadSales();
      BOOT.dashboard=await server('refreshDashboard');
    }catch(err){
      toast(err.message,true);
    }finally{
      showLoading(false);
    }
  }

'''

if 'function renderSalesPage()' not in html:
    html = must_replace(html, sales_ui_anchor, sales_ui + sales_ui_anchor, "sales client logic")

# ==========================================================
# 9. Final validation
# ==========================================================

required_code = [
    'FIXXIR_SALES_ORDER_HEADERS',
    'function createSale(payload)',
    'function getSale(salesId)',
    'function postSalePayment(payload)',
    'function ensureSalesSheets_(ss)',
]

required_html = [
    'data-page="sales"',
    'id="saleModal"',
    'function renderSalesPage()',
    'function submitSale(e)',
    'function openSale(id)',
]

missing = [x for x in required_code if x not in code] + [x for x in required_html if x not in html]
if missing:
    raise SystemExit("ERROR: Patch validation failed. Missing: " + ", ".join(missing))

if 'name="Customer_ID_Number"' in html:
    raise SystemExit("ERROR: ID Number field still exists after patch.")

code_path.write_text(code, encoding="utf-8")
html_path.write_text(html, encoding="utf-8")
PY

echo
echo "======================================================"
echo " Fixxir Sales Phase 1 patch applied"
echo "======================================================"
echo
echo "Changed:"
echo "  $CODE_FILE"
echo "  $INDEX_FILE"
echo
echo "Backups:"
echo "  ${CODE_FILE}.before-sales-phase1.bak"
echo "  ${INDEX_FILE}.before-sales-phase1.bak"
echo
echo "Review:"
echo "  git diff -- $CODE_FILE $INDEX_FILE"
echo
echo "Then deploy:"
echo "  npm run deploy"
echo
echo "Phase 1 includes:"
echo "  - ID Number removed from repair intake"
echo "  - Sales page enabled"
echo "  - Multiple sale items"
echo "  - Customer/contact selection"
echo "  - IMEI/serial capture"
echo "  - Unit cost + gross profit"
echo "  - Initial and later payments"
echo "  - Sales-linked Finance_Ledger entries"
echo
echo "Inventory stock deduction is intentionally NOT included yet."
