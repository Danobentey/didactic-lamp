/**
 * Fixxir Operations MVP
 * Google Apps Script backend for a Google Sheets database.
 *
 * First run:
 *   initializeFixxir('YOUR_GOOGLE_SHEET_ID');
 */

const FIXXIR = Object.freeze({
  sheets: {
    customers: "Customers",
    repairs: "Repairs",
    repairExpenses: "Repair_Expenses",
    technicians: "Technicians",
    suppliers: "Suppliers",
    inventory: "Inventory",
    serializedDevices: "Serialized_Devices",
    inventoryMovements: "Inventory_Movements",
    salesOrders: "Sales_Orders",
    salesItems: "Sales_Items",
    catalog: "Product_Catalog",
    quotes: "Quotes",
    quoteItems: "Quote_Items",
    finance: "Finance_Ledger",
    contacts: "Contacts",
    settings: "Settings",
  },
  prefixes: {
    Customers: "CUS",
    Repairs: "REP",
    Repair_Expenses: "REX",
    Technicians: "TEC",
    Suppliers: "SUP",
    Inventory: "PRD",
    Serialized_Devices: "DEV",
    Inventory_Movements: "MOV",
    Sales_Orders: "SAL",
    Sales_Items: "SIT",
    Product_Catalog: "CAT",
    Quotes: "QUO",
    Quote_Items: "QIT",
    Finance_Ledger: "TXN",
  },
  closedRepairStatuses: ["Completed", "Cancelled", "Returned Unrepaired"],
});

const FIXXIR_CONTACT_HEADERS = Object.freeze([
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

function doGet() {
  return HtmlService.createHtmlOutputFromFile("Index")
    .setTitle("Fixxir Operations")
    .addMetaTag("viewport", "width=device-width, initial-scale=1");
}

/**
 * Run this ONCE from the Apps Script editor after pasting the Sheet ID.
 */
function initializeFixxir(spreadsheetId) {
  const props = PropertiesService.getScriptProperties();

  // Resolution order:
  // 1. Explicit function argument
  // 2. Previously saved Script Property
  // 3. Bound/active Google Spreadsheet
  let id = String(spreadsheetId || "").trim();

  if (!id) {
    id = String(props.getProperty("FIXXIR_SPREADSHEET_ID") || "").trim();
  }

  if (!id) {
    try {
      const activeSpreadsheet = SpreadsheetApp.getActiveSpreadsheet();
      if (activeSpreadsheet) {
        id = activeSpreadsheet.getId();
      }
    } catch (error) {
      // Standalone Apps Script projects may not have an active spreadsheet.
    }
  }

  if (!id || id.length < 10) {
    throw new Error(
      "Fixxir could not determine the Google Spreadsheet automatically. " +
        "If this project is bound to the Fixxir Sheet, run setupFixxir() again. " +
        'If this is a standalone project, run initializeFixxir("YOUR_SPREADSHEET_ID") once.',
    );
  }

  const ss = SpreadsheetApp.openById(id);

  ensureContactsSheet_(ss);
  ensureSalesSheets_(ss);

  const requiredSheets = Object.values(FIXXIR.sheets);
  const missing = requiredSheets.filter((name) => !ss.getSheetByName(name));

  if (missing.length) {
    throw new Error(
      "The selected spreadsheet is missing required sheet(s): " +
        missing.join(", "),
    );
  }

  props.setProperty("FIXXIR_SPREADSHEET_ID", id);

  // Seed counters from existing IDs so future generated IDs do not collide.
  Object.entries(FIXXIR.prefixes).forEach(([sheetName, prefix]) => {
    seedCounter_(ss.getSheetByName(sheetName), prefix);
  });

  return {
    ok: true,
    spreadsheetId: id,
    spreadsheetName: ss.getName(),
    message: "Fixxir initialized successfully.",
  };
}

/**
 * Run this from the Apps Script editor using the normal Run button.
 *
 * If the project is bound to the Fixxir Google Sheet, the spreadsheet
 * is detected automatically and its ID is stored in Script Properties.
 *
 * If the project is standalone, use initializeFixxir("YOUR_SPREADSHEET_ID")
 * once instead.
 */
function setupFixxir() {
  return initializeFixxir();
}

/**
 * Optional. Run from the Apps Script editor to restrict the app to specific
 * signed-in Google accounts. Use commas between emails.
 *
 * Example: setAllowedEmails('sam@example.com,admin@example.com')
 *
 * Leave blank to rely only on Web App deployment access controls.
 */
function setAllowedEmails(csvEmails) {
  const value = String(csvEmails || "")
    .split(",")
    .map((x) => x.trim().toLowerCase())
    .filter(Boolean)
    .join(",");
  PropertiesService.getScriptProperties().setProperty(
    "FIXXIR_ALLOWED_EMAILS",
    value,
  );
  return value;
}

function getBootstrapData() {
  assertAuthorized_();
  return {
    appName: "Fixxir Operations",
    user: currentUser_(),
    settings: getSettings_(),
    technicians: getActiveTechnicians_(),
    dashboard: getDashboardData_(),
  };
}

function refreshDashboard() {
  assertAuthorized_();
  return getDashboardData_();
}

function listRepairs(filters) {
  assertAuthorized_();
  filters = filters || {};

  const repairs = getRecords_(FIXXIR.sheets.repairs);
  const customerMap = objectMap_(
    getRecords_(FIXXIR.sheets.customers),
    "Customer_ID",
  );
  const techMap = objectMap_(
    getRecords_(FIXXIR.sheets.technicians),
    "Technician_ID",
  );
  const financeSummary = buildRepairFinanceMap_();

  let rows = repairs.map((r) => {
    const fs = financeSummary[r.Repair_ID] || { credits: 0, debits: 0 };
    const finalAmount = number_(r.Final_Amount) || number_(r.Quoted_Amount);
    return Object.assign({}, r, {
      Customer_Name: customerMap[r.Customer_ID]
        ? customerMap[r.Customer_ID].Full_Name
        : "",
      Customer_Phone: customerMap[r.Customer_ID]
        ? customerMap[r.Customer_ID].Phone_Primary
        : "",
      Technician_Name: techMap[r.Technician_ID]
        ? techMap[r.Technician_ID].Full_Name
        : "",
      Amount_Paid_Calc: fs.credits,
      Balance_Calc: Math.max(0, finalAmount - fs.credits),
      Direct_Cost_Calc: fs.debits,
      Gross_Profit_Calc: finalAmount - fs.debits,
    });
  });

  const q = String(filters.q || "")
    .trim()
    .toLowerCase();
  const status = String(filters.status || "").trim();

  if (q) {
    rows = rows.filter((r) =>
      [
        r.Repair_ID,
        r.Customer_Name,
        r.Customer_Phone,
        r.Brand,
        r.Model,
        r.Serial_Number,
        r.IMEI_1,
        r.IMEI_2,
        r.Reported_Issue,
      ].some((v) =>
        String(v || "")
          .toLowerCase()
          .includes(q),
      ),
    );
  }
  if (status) rows = rows.filter((r) => r.Repair_Status === status);

  rows.sort((a, b) =>
    String(b.Date_Received || "").localeCompare(String(a.Date_Received || "")),
  );
  return rows.slice(0, 250);
}

function getRepair(repairId) {
  assertAuthorized_();
  const id = String(repairId || "").trim();
  if (!id) throw new Error("Repair ID is required.");

  const repair = findById_(FIXXIR.sheets.repairs, "Repair_ID", id);
  if (!repair) throw new Error("Repair not found: " + id);

  const customer = repair.Customer_ID
    ? findById_(FIXXIR.sheets.customers, "Customer_ID", repair.Customer_ID)
    : null;

  const technician = repair.Technician_ID
    ? findById_(
        FIXXIR.sheets.technicians,
        "Technician_ID",
        repair.Technician_ID,
      )
    : null;

  const transactions = getRecords_(FIXXIR.sheets.finance)
    .filter(
      (t) =>
        t.Repair_ID === id ||
        (t.Reference_Type === "Repair" && t.Reference_ID === id),
    )
    .sort((a, b) => String(b.Date || "").localeCompare(String(a.Date || "")));

  const credits = transactions
    .filter((t) => t.Transaction_Type === "Credit")
    .reduce((s, t) => s + number_(t.Amount), 0);

  const debits = transactions
    .filter((t) => t.Transaction_Type === "Debit")
    .reduce((s, t) => s + number_(t.Amount), 0);

  const finalAmount =
    number_(repair.Final_Amount) || number_(repair.Quoted_Amount);

  return {
    repair,
    customer,
    technician,
    transactions,
    summary: {
      revenue: finalAmount,
      paid: credits,
      balance: Math.max(0, finalAmount - credits),
      directCost: debits,
      grossProfit: finalAmount - debits,
    },
  };
}

function searchCustomers(query) {
  assertAuthorized_();
  const q = String(query || "")
    .trim()
    .toLowerCase();
  if (!q) return [];

  return getRecords_(FIXXIR.sheets.customers)
    .filter((c) =>
      [
        c.Customer_ID,
        c.Full_Name,
        c.Phone_Primary,
        c.Phone_Alternate,
        c.Email,
      ].some((v) =>
        String(v || "")
          .toLowerCase()
          .includes(q),
      ),
    )
    .slice(0, 30);
}

function importContactsCsv(csvText) {
  assertAuthorized_();

  let text = String(csvText || "").replace(/^\uFEFF/, "");
  if (!text.trim()) throw new Error("The selected contacts CSV is empty.");

  const parsed = Utilities.parseCsv(text);
  if (!parsed.length) throw new Error("No rows were found in the contacts CSV.");

  const incomingHeaders = parsed[0].map((h) =>
    String(h || "").replace(/^\uFEFF/, "").trim(),
  );

  const missing = FIXXIR_CONTACT_HEADERS.filter(
    (header) => !incomingHeaders.includes(header),
  );

  if (missing.length) {
    throw new Error(
      "This is not a normalized Fixxir contacts CSV. Missing column(s): " +
        missing.join(", "),
    );
  }

  const indexByHeader = {};
  incomingHeaders.forEach((header, index) => {
    indexByHeader[header] = index;
  });

  const data = parsed
    .slice(1)
    .filter((row) => row.some((value) => String(value || "").trim()))
    .map((row) =>
      FIXXIR_CONTACT_HEADERS.map((header) => {
        const index = indexByHeader[header];
        return index === undefined ? "" : row[index] || "";
      }),
    );

  const sh = ensureContactsSheet_(getSpreadsheet_());

  sh.clearContents();
  sh.getRange(1, 1, 1, FIXXIR_CONTACT_HEADERS.length).setValues([
    FIXXIR_CONTACT_HEADERS,
  ]);

  if (data.length) {
    sh.getRange(2, 1, data.length, FIXXIR_CONTACT_HEADERS.length).setValues(data);
  }

  sh.setFrozenRows(1);

  return {
    ok: true,
    imported: data.length,
    sheetName: FIXXIR.sheets.contacts,
  };
}

function searchCustomerSources(query) {
  assertAuthorized_();

  const raw = String(query || "").trim();
  const q = raw.toLowerCase();
  if (!q) return [];

  ensureContactsSheet_(getSpreadsheet_());

  const normalizedQueryPhone = normalizePhone_(raw);
  const allCustomers = getRecords_(FIXXIR.sheets.customers);

  const matchingCustomers = allCustomers
    .filter((c) => {
      const values = [
        c.Customer_ID,
        c.Full_Name,
        c.Phone_Primary,
        c.Phone_Alternate,
        c.Email,
      ];

      const textMatch = values.some((value) =>
        String(value || "").toLowerCase().includes(q),
      );

      const phoneMatch =
        normalizedQueryPhone.length >= 4 &&
        [c.Phone_Primary, c.Phone_Alternate].some((phone) =>
          normalizePhone_(phone).includes(normalizedQueryPhone),
        );

      return textMatch || phoneMatch;
    })
    .map((c) => Object.assign({}, c, { _Source: "Customer" }));

  const customerPhones = new Set();
  const customerEmails = new Set();

  allCustomers.forEach((customer) => {
    [customer.Phone_Primary, customer.Phone_Alternate].forEach((phone) => {
      const normalized = normalizePhone_(phone);
      if (normalized) customerPhones.add(normalized);
    });

    const email = String(customer.Email || "").trim().toLowerCase();
    if (email) customerEmails.add(email);
  });

  const matchingContacts = getRecords_(FIXXIR.sheets.contacts)
    .filter((contact) => {
      const contactPhones = [
        contact.Phone_Primary_Normalized,
        contact.Phone_Alternate_Normalized,
        contact.Phone_Primary,
        contact.Phone_Alternate,
      ].map(normalizePhone_).filter(Boolean);

      const contactEmails = String(contact.All_Emails || contact.Email || "")
        .split("|")
        .map((email) => email.trim().toLowerCase())
        .filter(Boolean);

      if (
        contactPhones.some((phone) => customerPhones.has(phone)) ||
        contactEmails.some((email) => customerEmails.has(email))
      ) {
        return false;
      }

      const values = [
        contact.Contact_ID,
        contact.Full_Name,
        contact.Phone_Primary,
        contact.Phone_Alternate,
        contact.All_Phones,
        contact.Email,
        contact.All_Emails,
        contact.Company,
        contact.Search_Key,
      ];

      const textMatch = values.some((value) =>
        String(value || "").toLowerCase().includes(q),
      );

      const phoneMatch =
        normalizedQueryPhone.length >= 4 &&
        contactPhones.some((phone) => phone.includes(normalizedQueryPhone));

      return textMatch || phoneMatch;
    })
    .map((contact) =>
      Object.assign({}, contact, {
        Customer_ID: "",
        _Source: "Contact",
      }),
    );

  return matchingCustomers
    .slice(0, 15)
    .concat(matchingContacts.slice(0, Math.max(0, 30 - matchingCustomers.length)))
    .slice(0, 30);
}

function ensureContactsSheet_(ss) {
  ss = ss || getSpreadsheet_();

  let sh = ss.getSheetByName(FIXXIR.sheets.contacts);
  if (!sh) sh = ss.insertSheet(FIXXIR.sheets.contacts);

  const currentHeader =
    sh.getLastColumn() > 0
      ? sh.getRange(1, 1, 1, sh.getLastColumn()).getValues()[0]
      : [];

  const hasHeader = FIXXIR_CONTACT_HEADERS.every(
    (header, index) => String(currentHeader[index] || "").trim() === header,
  );

  if (!hasHeader && sh.getLastRow() <= 1) {
    sh.clearContents();
    sh.getRange(1, 1, 1, FIXXIR_CONTACT_HEADERS.length).setValues([
      FIXXIR_CONTACT_HEADERS,
    ]);
    sh.setFrozenRows(1);
  }

  return sh;
}

function createCustomer(payload) {
  assertAuthorized_();
  payload = payload || {};
  requireFields_(payload, ["Full_Name", "Phone_Primary"]);

  const phone = normalizePhone_(payload.Phone_Primary);
  const existing = getRecords_(FIXXIR.sheets.customers).find(
    (c) => normalizePhone_(c.Phone_Primary) === phone && phone,
  );
  if (existing) return existing;

  const id = generateId_(FIXXIR.sheets.customers);
  const now = new Date();

  appendRecord_(FIXXIR.sheets.customers, {
    Customer_ID: id,
    Customer_Type: payload.Customer_Type || "Individual",
    Full_Name: clean_(payload.Full_Name),
    Phone_Primary: clean_(payload.Phone_Primary),
    Phone_Alternate: clean_(payload.Phone_Alternate),
    Email: clean_(payload.Email),
    Address: clean_(payload.Address),
    Date_of_Birth: parseDate_(payload.Date_of_Birth),
    Date_Created: now,
    Status: "Active",
    Notes: clean_(payload.Notes),
  });

  return findById_(FIXXIR.sheets.customers, "Customer_ID", id);
}

function createRepair(payload) {
  assertAuthorized_();
  payload = payload || {};
  requireFields_(payload, ["Device_Type", "Brand", "Model", "Reported_Issue"]);

  let customerId = clean_(payload.Customer_ID);

  if (!customerId) {
    requireFields_(payload, ["Customer_Name", "Customer_Phone"]);
    const customer = createCustomer({
      Customer_Type: payload.Customer_Type || "Individual",
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

  const id = generateId_(FIXXIR.sheets.repairs);
  const now = new Date();

  appendRecord_(FIXXIR.sheets.repairs, {
    Repair_ID: id,
    Date_Received: now,
    Customer_ID: customerId,
    Device_Type: clean_(payload.Device_Type),
    Brand: clean_(payload.Brand),
    Model: clean_(payload.Model),
    Serial_Number: clean_(payload.Serial_Number),
    IMEI_1: clean_(payload.IMEI_1),
    IMEI_2: clean_(payload.IMEI_2),
    Color: clean_(payload.Color),
    Storage: clean_(payload.Storage),
    Accessories_Received: clean_(payload.Accessories_Received),
    Reported_Issue: clean_(payload.Reported_Issue),
    Physical_Condition: clean_(payload.Physical_Condition),
    Diagnosis: clean_(payload.Diagnosis),
    Technician_ID: clean_(payload.Technician_ID),
    Repair_Status: clean_(payload.Repair_Status) || "Received",
    Priority: clean_(payload.Priority) || "Normal",
    Expected_Completion: parseDate_(payload.Expected_Completion),
    Quoted_Amount: number_(payload.Quoted_Amount),
    Final_Amount: numberOrBlank_(payload.Final_Amount),
    QA_Status: "Not Started",
    Warranty_Days: integer_(payload.Warranty_Days),
    Collection_Method: clean_(payload.Collection_Method),
    Created_By: currentUser_(),
    Last_Updated: now,
    Notes: clean_(payload.Notes),
  });

  return getRepair(id);
}

function updateRepair(payload) {
  assertAuthorized_();
  payload = payload || {};
  const repairId = clean_(payload.Repair_ID);
  if (!repairId) throw new Error("Repair_ID is required.");

  const allowed = [
    "Diagnosis",
    "Technician_ID",
    "Repair_Status",
    "Priority",
    "Expected_Completion",
    "Quoted_Amount",
    "Final_Amount",
    "QA_Status",
    "QA_Notes",
    "Date_Completed",
    "Warranty_Days",
    "Collection_Method",
    "Collected_By",
    "Notes",
  ];

  const updates = {};
  allowed.forEach((k) => {
    if (Object.prototype.hasOwnProperty.call(payload, k)) {
      if (["Quoted_Amount", "Final_Amount"].includes(k))
        updates[k] = numberOrBlank_(payload[k]);
      else if (k === "Warranty_Days") updates[k] = integer_(payload[k]);
      else if (["Expected_Completion", "Date_Completed"].includes(k))
        updates[k] = parseDate_(payload[k]);
      else updates[k] = clean_(payload[k]);
    }
  });
  updates.Last_Updated = new Date();

  updateRecordById_(FIXXIR.sheets.repairs, "Repair_ID", repairId, updates);
  return getRepair(repairId);
}

/* ---------------- Sales ---------------- */

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
      grossProfit: active
        .filter((row) => row.Cost_Status_Calc === "Known")
        .reduce((sum, row) => sum + number_(row.Gross_Profit_Calc), 0),
      profitPending: active.filter((row) => row.Cost_Status_Calc !== "Known").length,
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
        allCostsKnown: true,
        hasEstimatedCost: false,
        names: [],
        search: [],
      };
    }

    const bucket = itemMap[id];
    bucket.itemCount += 1;
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
      allCostsKnown: true,
      hasEstimatedCost: false,
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
      Cost_Status_Calc: itemSummary.allCostsKnown
        ? "Known"
        : itemSummary.hasEstimatedCost
          ? "Estimated / Pending"
          : "Pending",
      Gross_Profit_Calc: itemSummary.allCostsKnown
        ? total - itemSummary.costTotal
        : "",
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
      costStatus: allCostsKnown
        ? "Known"
        : hasEstimatedCost
          ? "Estimated / Pending"
          : "Pending",
      grossProfit: allCostsKnown ? total - costTotal : "",
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

/* ---------------- Flexible Sales / Catalog / Quotes ---------------- */

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

function postFinance(payload) {
  assertAuthorized_();
  payload = payload || {};
  requireFields_(payload, [
    "Transaction_Type",
    "Category",
    "Amount",
    "Payment_Method",
  ]);

  const type = clean_(payload.Transaction_Type);
  if (!["Credit", "Debit"].includes(type))
    throw new Error("Transaction type must be Credit or Debit.");

  const amount = number_(payload.Amount);
  if (!(amount > 0)) throw new Error("Amount must be greater than zero.");

  const repairId = clean_(payload.Repair_ID);
  const salesId = clean_(payload.Sales_ID);
  const refType =
    clean_(payload.Reference_Type) ||
    (repairId ? "Repair" : salesId ? "Sale" : "General");
  const refId = clean_(payload.Reference_ID) || repairId || salesId;

  if (repairId && !findById_(FIXXIR.sheets.repairs, "Repair_ID", repairId)) {
    throw new Error("Repair not found: " + repairId);
  }

  if (salesId && !findById_(FIXXIR.sheets.salesOrders, "Sales_ID", salesId)) {
    throw new Error("Sale not found: " + salesId);
  }

  const txnId = generateId_(FIXXIR.sheets.finance);
  appendRecord_(FIXXIR.sheets.finance, {
    Transaction_ID: txnId,
    Date: parseDate_(payload.Date) || new Date(),
    Transaction_Type: type,
    Category: clean_(payload.Category),
    Amount: amount,
    Payment_Method: clean_(payload.Payment_Method),
    Account: clean_(payload.Account) || "Operating",
    Repair_ID: repairId,
    Sales_ID: salesId,
    Reference_Type: refType,
    Reference_ID: refId,
    Customer_ID: clean_(payload.Customer_ID),
    Supplier_ID: clean_(payload.Supplier_ID),
    Technician_ID: clean_(payload.Technician_ID),
    Description: clean_(payload.Description),
    Receipt_Reference: clean_(payload.Receipt_Reference),
    Entered_By: currentUser_(),
    Approval_Status: clean_(payload.Approval_Status) || "Approved",
    Notes: clean_(payload.Notes),
  });

  // Mirror repair-specific debits into Repair_Expenses for operational reporting.
  if (repairId && type === "Debit") {
    const expenseTypeMap = {
      "Repair Parts": "Parts",
      "Technician Payment": "Technician",
      Logistics: "Logistics",
      Refund: "Refund",
    };
    const expenseType = expenseTypeMap[payload.Category] || "Other";
    appendRecord_(FIXXIR.sheets.repairExpenses, {
      Repair_Expense_ID: generateId_(FIXXIR.sheets.repairExpenses),
      Repair_ID: repairId,
      Date: parseDate_(payload.Date) || new Date(),
      Expense_Type: expenseType,
      Payee_Type: clean_(payload.Payee_Type),
      Payee_ID_or_Name: clean_(payload.Payee_ID_or_Name),
      Description: clean_(payload.Description),
      Amount: amount,
      Payment_Method: clean_(payload.Payment_Method),
      Finance_Transaction_ID: txnId,
      Entered_By: currentUser_(),
      Notes: clean_(payload.Notes),
    });
  }

  return repairId ? getRepair(repairId) : { transactionId: txnId };
}

/* ---------------- Dashboard ---------------- */

function getDashboardData_() {
  const customers = getRecords_(FIXXIR.sheets.customers);
  const repairs = getRecords_(FIXXIR.sheets.repairs);
  const finance = getRecords_(FIXXIR.sheets.finance);
  const financeMap = buildRepairFinanceMap_(finance);

  const openRepairs = repairs.filter(
    (r) => !FIXXIR.closedRepairStatuses.includes(r.Repair_Status),
  );
  const ready = repairs.filter((r) => r.Repair_Status === "Ready for Pickup");

  let outstanding = 0;
  repairs.forEach((r) => {
    if (
      FIXXIR.closedRepairStatuses.includes(r.Repair_Status) &&
      r.Repair_Status !== "Completed"
    )
      return;
    const revenue = number_(r.Final_Amount) || number_(r.Quoted_Amount);
    const paid = (financeMap[r.Repair_ID] || { credits: 0 }).credits;
    outstanding += Math.max(0, revenue - paid);
  });

  const today = Utilities.formatDate(
    new Date(),
    Session.getScriptTimeZone(),
    "yyyy-MM-dd",
  );
  let todayCredits = 0,
    todayDebits = 0;
  finance.forEach((t) => {
    const txnDate = dateKey_(t.Date);
    if (txnDate !== today) return;
    if (t.Transaction_Type === "Credit") todayCredits += number_(t.Amount);
    if (t.Transaction_Type === "Debit") todayDebits += number_(t.Amount);
  });

  const customerMap = objectMap_(customers, "Customer_ID");
  const recent = repairs
    .slice()
    .sort((a, b) =>
      String(b.Date_Received || "").localeCompare(
        String(a.Date_Received || ""),
      ),
    )
    .slice(0, 8)
    .map((r) => ({
      Repair_ID: r.Repair_ID,
      Date_Received: r.Date_Received,
      Customer_Name: customerMap[r.Customer_ID]
        ? customerMap[r.Customer_ID].Full_Name
        : "",
      Device: [r.Brand, r.Model].filter(Boolean).join(" "),
      Repair_Status: r.Repair_Status,
      Priority: r.Priority,
    }));

  return {
    totalCustomers: customers.length,
    openRepairs: openRepairs.length,
    readyForPickup: ready.length,
    outstandingRepairBalances: outstanding,
    todayCredits,
    todayDebits,
    netToday: todayCredits - todayDebits,
    recentRepairs: recent,
  };
}

/* ---------------- Data helpers ---------------- */

function getSpreadsheet_() {
  const id = PropertiesService.getScriptProperties().getProperty(
    "FIXXIR_SPREADSHEET_ID",
  );
  if (!id)
    throw new Error(
      'Fixxir has not been initialized. Run initializeFixxir("SHEET_ID") from the Apps Script editor.',
    );
  return SpreadsheetApp.openById(id);
}

function getSheet_(sheetName) {
  const sheet = getSpreadsheet_().getSheetByName(sheetName);
  if (!sheet) throw new Error("Required sheet not found: " + sheetName);
  return sheet;
}

function getRecords_(sheetName) {
  const sh = getSheet_(sheetName);
  const values = sh.getDataRange().getValues();
  if (values.length < 2) return [];
  const headers = values[0].map(String);
  return values
    .slice(1)
    .filter((row) => row.some((v) => v !== "" && v !== null))
    .map((row) => {
      const obj = {};
      headers.forEach((h, i) => (obj[h] = serialize_(row[i])));
      return obj;
    });
}

function appendRecord_(sheetName, record) {
  const sh = getSheet_(sheetName);
  const lastCol = sh.getLastColumn();
  const headers = sh.getRange(1, 1, 1, lastCol).getValues()[0].map(String);
  const row = headers.map((h) =>
    Object.prototype.hasOwnProperty.call(record, h) ? record[h] : "",
  );
  sh.appendRow(row);
}

function findById_(sheetName, keyName, id) {
  return (
    getRecords_(sheetName).find((r) => String(r[keyName]) === String(id)) ||
    null
  );
}

function updateRecordById_(sheetName, keyName, id, updates) {
  const sh = getSheet_(sheetName);
  const range = sh.getDataRange();
  const values = range.getValues();
  if (!values.length) throw new Error("Empty sheet: " + sheetName);
  const headers = values[0].map(String);
  const keyIndex = headers.indexOf(keyName);
  if (keyIndex < 0) throw new Error("Key column not found: " + keyName);

  const rowIndex = values.findIndex(
    (row, i) => i > 0 && String(row[keyIndex]) === String(id),
  );
  if (rowIndex < 0) throw new Error("Record not found: " + id);

  const row = values[rowIndex].slice();
  Object.entries(updates).forEach(([key, value]) => {
    const colIndex = headers.indexOf(key);
    if (colIndex >= 0) row[colIndex] = value;
  });
  sh.getRange(rowIndex + 1, 1, 1, headers.length).setValues([row]);
}

function generateId_(sheetName) {
  const prefix = FIXXIR.prefixes[sheetName];
  if (!prefix) throw new Error("No ID prefix configured for " + sheetName);

  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    const props = PropertiesService.getScriptProperties();
    const key = "FIXXIR_COUNTER_" + prefix;
    let current = Number(props.getProperty(key) || 0);

    if (!current) {
      const sh = getSheet_(sheetName);
      current = maxIdNumber_(sh, prefix);
    }

    current += 1;
    props.setProperty(key, String(current));
    return prefix + "-" + String(current).padStart(6, "0");
  } finally {
    lock.releaseLock();
  }
}

function seedCounter_(sheet, prefix) {
  const props = PropertiesService.getScriptProperties();
  const key = "FIXXIR_COUNTER_" + prefix;
  const max = maxIdNumber_(sheet, prefix);
  const existing = Number(props.getProperty(key) || 0);
  if (max > existing) props.setProperty(key, String(max));
}

function maxIdNumber_(sheet, prefix) {
  const lastRow = sheet.getLastRow();
  if (lastRow < 2) return 0;
  const ids = sheet
    .getRange(2, 1, lastRow - 1, 1)
    .getDisplayValues()
    .flat();
  const re = new RegExp("^" + prefix + "-(\\d+)$");
  return ids.reduce((max, id) => {
    const m = String(id).match(re);
    return m ? Math.max(max, Number(m[1])) : max;
  }, 0);
}

function getSettings_() {
  const sh = getSheet_(FIXXIR.sheets.settings);
  const values = sh.getDataRange().getDisplayValues();
  if (!values.length) return {};
  const headers = values[0];
  const out = {};
  headers.forEach((header, col) => {
    if (!header) return;
    out[header] = values
      .slice(1)
      .map((row) => row[col])
      .filter(Boolean);
  });
  return out;
}

function getActiveTechnicians_() {
  return getRecords_(FIXXIR.sheets.technicians)
    .filter((t) => !t.Status || t.Status === "Active")
    .map((t) => ({
      Technician_ID: t.Technician_ID,
      Full_Name: t.Full_Name,
      Specialty: t.Specialty,
    }));
}

function buildRepairFinanceMap_(financeRows) {
  const rows = financeRows || getRecords_(FIXXIR.sheets.finance);
  const map = {};
  rows.forEach((t) => {
    const id =
      t.Repair_ID || (t.Reference_Type === "Repair" ? t.Reference_ID : "");
    if (!id) return;
    if (!map[id]) map[id] = { credits: 0, debits: 0 };
    if (t.Transaction_Type === "Credit") map[id].credits += number_(t.Amount);
    if (t.Transaction_Type === "Debit") map[id].debits += number_(t.Amount);
  });
  return map;
}

function objectMap_(rows, key) {
  return rows.reduce((out, row) => {
    if (row[key]) out[row[key]] = row;
    return out;
  }, {});
}

/* ---------------- Validation / serialization ---------------- */

function assertAuthorized_() {
  const allowedCsv =
    PropertiesService.getScriptProperties().getProperty(
      "FIXXIR_ALLOWED_EMAILS",
    ) || "";
  if (!allowedCsv) return true;

  const allowed = allowedCsv
    .split(",")
    .map((x) => x.trim().toLowerCase())
    .filter(Boolean);
  const email = String(Session.getActiveUser().getEmail() || "").toLowerCase();

  if (!email || !allowed.includes(email)) {
    throw new Error(
      "This Google account is not authorized to use Fixxir Operations.",
    );
  }
  return true;
}

function currentUser_() {
  return (
    Session.getActiveUser().getEmail() ||
    Session.getEffectiveUser().getEmail() ||
    "Unknown user"
  );
}

function requireFields_(obj, fields) {
  const missing = fields.filter(
    (k) =>
      obj[k] === undefined || obj[k] === null || String(obj[k]).trim() === "",
  );
  if (missing.length)
    throw new Error("Required field(s): " + missing.join(", "));
}

function clean_(value) {
  return value === undefined || value === null ? "" : String(value).trim();
}

function number_(value) {
  if (value === "" || value === null || value === undefined) return 0;
  const n = Number(String(value).replace(/[₦,\s]/g, ""));
  return Number.isFinite(n) ? n : 0;
}

function numberOrBlank_(value) {
  if (value === "" || value === null || value === undefined) return "";
  return number_(value);
}

function integer_(value) {
  if (value === "" || value === null || value === undefined) return "";
  const n = parseInt(value, 10);
  return Number.isFinite(n) ? n : "";
}

function normalizePhone_(value) {
  let digits = String(value || "").replace(/\D/g, "");

  if (digits.startsWith("234") && digits.length >= 13) {
    digits = "0" + digits.slice(3);
  }

  return digits;
}

function parseDate_(value) {
  if (!value) return "";
  if (value instanceof Date) return value;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? "" : d;
}

function serialize_(value) {
  if (value instanceof Date) {
    return Utilities.formatDate(
      value,
      Session.getScriptTimeZone(),
      "yyyy-MM-dd'T'HH:mm:ss",
    );
  }
  return value;
}

function dateKey_(value) {
  if (!value) return "";
  const d = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(d.getTime())) return String(value).slice(0, 10);
  return Utilities.formatDate(d, Session.getScriptTimeZone(), "yyyy-MM-dd");
}
