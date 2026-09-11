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
        c.ID_Number,
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
        c.ID_Number,
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
    ID_Type: clean_(payload.ID_Type),
    ID_Number: clean_(payload.ID_Number),
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
      ID_Type: payload.Customer_ID_Type,
      ID_Number: payload.Customer_ID_Number,
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
