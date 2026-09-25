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
    staffUsers: "Staff_Users",
    repairs: "Repairs",
    repairExpenses: "Repair_Expenses",
    technicians: "Technicians",
    suppliers: "Suppliers",
    supplierCatalog: "Supplier_Catalog",
    purchases: "Purchases",
    purchaseItems: "Purchase_Items",
    purchaseExpenses: "Purchase_Expenses",
    inventory: "Inventory",
    serializedDevices: "Serialized_Devices",
    inventoryMovements: "Inventory_Movements",
    salesOrders: "Sales_Orders",
    salesItems: "Sales_Items",
    catalog: "Product_Catalog",
    quotes: "Quotes",
    quoteItems: "Quote_Items",
    finance: "Finance_Ledger",
    generalExpenses: "General_Expenses",
    settlements: "Settlements",
    settlementAllocations: "Settlement_Allocations",
    entityNotes: "Entity_Notes",
    contacts: "Contacts",
    settings: "Settings",
  },
  prefixes: {
    Customers: "CUS",
    Staff_Users: "STF",
    Repairs: "REP",
    Repair_Expenses: "REX",
    Technicians: "TEC",
    Suppliers: "SUP",
    Supplier_Catalog: "VIT",
    Purchases: "PUR",
    Purchase_Items: "PIT",
    Purchase_Expenses: "PEX",
    Inventory: "PRD",
    Serialized_Devices: "DEV",
    Inventory_Movements: "MOV",
    Sales_Orders: "SAL",
    Sales_Items: "SIT",
    Product_Catalog: "CAT",
    Quotes: "QUO",
    Quote_Items: "QIT",
    Finance_Ledger: "TXN",
    General_Expenses: "GEX",
    Settlements: "STL",
    Settlement_Allocations: "STA",
    Entity_Notes: "NTE",
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


/* FIXXIR_ENTITY_NOTES_V1 */

const FIXXIR_ENTITY_NOTE_HEADERS = Object.freeze([
  "Note_ID",
  "Reference_Type",
  "Reference_ID",
  "Note_Date",
  "Note",
  "Created_At",
  "Created_By",
]);


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


/* FIXXIR_STAFF_AUTH_V1 */

const FIXXIR_STAFF_USER_HEADERS = Object.freeze([
  "Staff_ID",
  "Full_Name",
  "Email",
  "PIN_Salt",
  "PIN_Hash",
  "Role",
  "Status",
  "Created_At",
  "Created_By",
  "Last_Login",
]);

let FIXXIR_RUNTIME_STAFF_ = null;

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
  ensureProcurementSchema_(ss);
  ensureSaleProcurementSchema_(ss);
  ensureRepairDateSchema_(ss);
  ensureEntityNotesSheet_(ss);

  ensureFinanceOperationsSchema_(ss);

  ensureAuditIdentitySchema_(ss);

  ensureStaffAuthSchema_(ss);

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
    suppliers: getActiveSuppliers_(),
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
  addSettlementRepairCostsToFinanceMap_(financeSummary);

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
    repairDateKey_(b).localeCompare(repairDateKey_(a)),
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

  const entityNotes = getEntityNotes_("Repair", id);

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

  const settlementAllocations = getSettlementAllocationsFor_(
    "Repair",
    id,
  );
  const settlementCosts = settlementAllocations.reduce(
    (sum, row) => sum + number_(row.Amount),
    0,
  );

  const finalAmount =
    number_(repair.Final_Amount) || number_(repair.Quoted_Amount);

  return {
    repair,
    customer,
    technician,
    notes: entityNotes,
    transactions,
    settlementAllocations,
    summary: {
      revenue: finalAmount,
      paid: credits,
      balance: Math.max(0, finalAmount - credits),
      directCost: debits + settlementCosts,
      settlementCosts,
      grossProfit: finalAmount - debits - settlementCosts,
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

  const repairDate = parseDate_(payload.Repair_Date) || now;

  appendRecord_(FIXXIR.sheets.repairs, {
    Repair_ID: id,
    Repair_Date: repairDate,
    Date_Received: repairDate,
    Created_At: now,
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
    Last_Updated_By: currentUser_(),
    Notes: clean_(payload.Notes),
  });

  return getRepair(id);
}

function updateRepair(payload) {
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
      Sale_Expense_Calc: finance.debits,
      Gross_Profit_Calc: itemSummary.allCostsKnown
        ? total - itemSummary.costTotal
        : "",
      Contribution_Calc: itemSummary.allCostsKnown
        ? total - itemSummary.costTotal - finance.debits
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
    Sales_Status: clean_(payload.Sales_Status) || "Pending Fulfilment",
    Subtotal: subtotal,
    Discount_Amount: discount,
    Total_Amount: total,
    Amount_Paid: initialPayment,
    Balance: Math.max(0, total - initialPayment),
    Payment_Status: salePaymentStatus_(total, initialPayment),
    Payment_Method: clean_(payload.Payment_Method),
    Created_By: currentUser_(),
    Last_Updated: now,
    Last_Updated_By: currentUser_(),
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

  if (clean_(payload.Sales_Status) !== "Cancelled") {
    ensureSaleProcurementForSale_(salesId);
  }

  return getSale(salesId);
}

function postSalePayment(payload) {
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
}

function syncSalePaymentFields_(salesId) {
  const sale = getSale(salesId);

  updateRecordById_(FIXXIR.sheets.salesOrders, "Sales_ID", salesId, {
    Amount_Paid: sale.summary.paid,
    Balance: sale.summary.balance,
    Payment_Status: sale.summary.paymentStatus,
    Last_Updated: new Date(),
    Last_Updated_By: currentUser_(),
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
    Last_Updated_By: currentUser_(),
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
    Last_Updated_By: currentUser_(),
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
    Last_Updated_By: currentUser_(),
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


/* ---------------- Procurement / Vendor Catalog ---------------- */

function getProcurementPageData(filters) {
  assertAuthorized_();
  ensureProcurementSchema_(getSpreadsheet_());
  ensureSaleProcurementSchema_(getSpreadsheet_());
  backfillSaleProcurement_();

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
    Last_Updated_By: currentUser_(),
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

  const entityNotes = getEntityNotes_("Purchase", id);

  const expenses = getRecords_(FIXXIR.sheets.purchaseExpenses)
    .filter((expense) => expense.Purchase_ID === id);

  const settlementAllocations = getSettlementAllocationsFor_(
    "Purchase",
    id,
  );
  const supplierSettled = settlementAllocations
    .filter((row) => row.Payee_Type === "Vendor")
    .reduce((sum, row) => sum + number_(row.Amount), 0);
  const supplierDue = number_(purchase.Items_Subtotal);

  const linkedSale = purchase.Sales_ID
    ? findById_(
        FIXXIR.sheets.salesOrders,
        "Sales_ID",
        purchase.Sales_ID,
      )
    : null;

  return {
    purchase,
    linkedSale,
    supplier,
    items,
    expenses,
    settlementAllocations,
    settlementSummary: {
      supplierDue,
      supplierSettled,
      supplierBalance: Math.max(0, supplierDue - supplierSettled),
      supplierOverpaid: Math.max(0, supplierSettled - supplierDue),
    },
    notes: entityNotes,
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
    Sales_ID: clean_(payload.Sales_ID),
    Purchase_Source: clean_(payload.Sales_ID) ? "Sale" : "Manual",
    Request_Date: parseDate_(payload.Request_Date) || purchaseDate,
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
    Last_Updated_By: currentUser_(),
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
      Sales_Item_ID: clean_(item.Sales_Item_ID),
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
    Last_Updated_By: currentUser_(),
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
      Last_Updated_By: currentUser_(),
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

/* FIXXIR_BULK_WORKFLOW_V2 */

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
}

/* ---------------- Repair / Purchase Notes ---------------- */

function addEntityNote(payload) {
  assertAuthorized_();
  ensureEntityNotesSheet_(getSpreadsheet_());

  payload = payload || {};

  const referenceType = clean_(payload.Reference_Type);
  const referenceId = clean_(payload.Reference_ID);
  const note = clean_(payload.Note);

  if (!["Repair", "Purchase"].includes(referenceType)) {
    throw new Error("Notes can currently be added only to Repairs or Purchases.");
  }

  if (!referenceId) throw new Error("Reference ID is required.");
  if (!note) throw new Error("Note cannot be empty.");

  if (
    referenceType === "Repair" &&
    !findById_(FIXXIR.sheets.repairs, "Repair_ID", referenceId)
  ) {
    throw new Error("Repair not found: " + referenceId);
  }

  if (
    referenceType === "Purchase" &&
    !findById_(FIXXIR.sheets.purchases, "Purchase_ID", referenceId)
  ) {
    throw new Error("Purchase not found: " + referenceId);
  }

  const now = new Date();
  const noteId = generateId_(FIXXIR.sheets.entityNotes);

  appendRecord_(FIXXIR.sheets.entityNotes, {
    Note_ID: noteId,
    Reference_Type: referenceType,
    Reference_ID: referenceId,
    Note_Date: now,
    Note: note,
    Created_At: now,
    Created_By: currentUser_(),
  });

  return {
    ok: true,
    note: findById_(FIXXIR.sheets.entityNotes, "Note_ID", noteId),
  };
}

function getEntityNotes_(referenceType, referenceId) {
  ensureEntityNotesSheet_(getSpreadsheet_());

  return getRecords_(FIXXIR.sheets.entityNotes)
    .filter(
      (row) =>
        row.Reference_Type === referenceType &&
        row.Reference_ID === referenceId,
    )
    .sort((a, b) => {
      const dateCmp = String(b.Note_Date || "").localeCompare(
        String(a.Note_Date || ""),
      );
      if (dateCmp) return dateCmp;
      return String(b.Note_ID || "").localeCompare(String(a.Note_ID || ""));
    });
}

function ensureEntityNotesSheet_(ss) {
  ss = ss || getSpreadsheet_();

  let sh = ss.getSheetByName(FIXXIR.sheets.entityNotes);
  if (!sh) sh = ss.insertSheet(FIXXIR.sheets.entityNotes);

  const lastCol = sh.getLastColumn();

  if (!lastCol) {
    sh.getRange(1, 1, 1, FIXXIR_ENTITY_NOTE_HEADERS.length).setValues([
      FIXXIR_ENTITY_NOTE_HEADERS,
    ]);
    sh.setFrozenRows(1);
    return sh;
  }

  const existingHeaders = sh
    .getRange(1, 1, 1, lastCol)
    .getValues()[0]
    .map((header) => String(header || "").trim());

  const missing = FIXXIR_ENTITY_NOTE_HEADERS.filter(
    (header) => !existingHeaders.includes(header),
  );

  if (missing.length) {
    sh.getRange(1, lastCol + 1, 1, missing.length).setValues([missing]);
  }

  sh.setFrozenRows(1);
  return sh;
}


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

/* ---------------- Audit identity schema ---------------- */

function ensureAuditIdentitySchema_(ss) {
  ss = ss || getSpreadsheet_();

  [
    [FIXXIR.sheets.repairs, ["Created_By", "Last_Updated", "Last_Updated_By"]],
    [FIXXIR.sheets.purchases, ["Created_By", "Last_Updated", "Last_Updated_By"]],
    [FIXXIR.sheets.salesOrders, ["Created_By", "Last_Updated", "Last_Updated_By"]],
    [FIXXIR.sheets.quotes, ["Created_By", "Last_Updated", "Last_Updated_By"]],
    [FIXXIR.sheets.catalog, ["Last_Updated", "Last_Updated_By"]],
    [FIXXIR.sheets.supplierCatalog, ["Last_Updated", "Last_Updated_By"]]
  ].forEach(([sheetName, headers]) => {
    if (sheetName) ensureSheetColumns_(ss, sheetName, headers);
  });
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
  requireRuntimeStaff_();
  return true;
}

function currentUser_() {
  return requireRuntimeStaff_().email;
}

function currentStaff_() {
  return requireRuntimeStaff_();
}

function getCurrentUserIdentity() {
  const staff = requireRuntimeStaff_();
  return {
    email: staff.email,
    fullName: staff.fullName,
    role: staff.role,
    effectiveUser: String(Session.getEffectiveUser().getEmail() || "")
      .trim()
      .toLowerCase(),
  };
}

/* ---------------- Internal Staff Authentication ---------------- */

function ensureStaffAuthSchema_(ss) {
  ss = ss || getSpreadsheet_();

  let sh = ss.getSheetByName(FIXXIR.sheets.staffUsers);
  if (!sh) sh = ss.insertSheet(FIXXIR.sheets.staffUsers);

  const lastCol = sh.getLastColumn();

  if (!lastCol) {
    sh.getRange(1, 1, 1, FIXXIR_STAFF_USER_HEADERS.length)
      .setValues([FIXXIR_STAFF_USER_HEADERS]);
    sh.setFrozenRows(1);
    return sh;
  }

  const headers = sh
    .getRange(1, 1, 1, lastCol)
    .getValues()[0]
    .map((header) => String(header || "").trim());

  const missing = FIXXIR_STAFF_USER_HEADERS.filter(
    (header) => !headers.includes(header),
  );

  if (missing.length) {
    sh.getRange(1, lastCol + 1, 1, missing.length)
      .setValues([missing]);
  }

  sh.setFrozenRows(1);
  return sh;
}

function loginStaff(email, pin) {
  ensureStaffAuthSchema_(getSpreadsheet_());

  const normalizedEmail = String(email || "").trim().toLowerCase();
  const cleanPin = String(pin || "").trim();

  if (!normalizedEmail || !cleanPin) {
    throw new Error("Enter your staff email and PIN.");
  }

  const staff = getRecords_(FIXXIR.sheets.staffUsers).find(
    (row) =>
      String(row.Email || "").trim().toLowerCase() === normalizedEmail,
  );

  if (!staff || String(staff.Status || "Active") !== "Active") {
    throw new Error("Invalid staff email or PIN.");
  }

  if (
    String(staff.PIN_Hash || "") !==
    staffPinHash_(cleanPin, staff.PIN_Salt)
  ) {
    throw new Error("Invalid staff email or PIN.");
  }

  const token = Utilities.getUuid() + Utilities.getUuid();
  const session = {
    staffId: staff.Staff_ID,
    email: normalizedEmail,
    fullName: clean_(staff.Full_Name) || normalizedEmail,
    role: clean_(staff.Role) || "Staff",
  };

  putStaffSession_(token, session);

  updateRecordById_(
    FIXXIR.sheets.staffUsers,
    "Staff_ID",
    staff.Staff_ID,
    { Last_Login: new Date() },
  );

  return { token, user: session };
}

function resumeStaffSession(token) {
  const session = getStaffSession_(token);
  if (!session) throw new Error("STAFF_SESSION_EXPIRED");

  putStaffSession_(token, session);
  return { ok: true, user: session };
}

function logoutStaff(token) {
  const key = staffSessionKey_(token);
  if (key) CacheService.getScriptCache().remove(key);
  return { ok: true };
}

function invokeWithStaffSession(methodName, hasArg, arg, token) {
  const session = getStaffSession_(token);
  if (!session) throw new Error("STAFF_SESSION_EXPIRED");

  const method = String(methodName || "").trim();

  if (!/^[A-Za-z_$][A-Za-z0-9_$]*$/.test(method)) {
    throw new Error("Invalid Fixxir method.");
  }

  const blocked = [
    "loginStaff",
    "resumeStaffSession",
    "logoutStaff",
    "invokeWithStaffSession",
    "adminCreateStaffUser",
    "adminResetStaffPin",
    "adminSetStaffStatus",
    "adminListStaffUsers",
    "initializeFixxir",
    "setupFixxir",
    "setAllowedEmails",
  ];

  if (blocked.includes(method) || method.endsWith("_")) {
    throw new Error("This Fixxir method cannot be called from the app.");
  }

  const fn = globalThis[method];
  if (typeof fn !== "function") {
    throw new Error("Unknown Fixxir method: " + method);
  }

  FIXXIR_RUNTIME_STAFF_ = session;
  putStaffSession_(token, session);

  try {
    return hasArg ? fn(arg) : fn();
  } finally {
    FIXXIR_RUNTIME_STAFF_ = null;
  }
}

function requireRuntimeStaff_() {
  if (!FIXXIR_RUNTIME_STAFF_) {
    throw new Error("STAFF_SESSION_EXPIRED");
  }
  return FIXXIR_RUNTIME_STAFF_;
}

function getStaffSession_(token) {
  const key = staffSessionKey_(token);
  if (!key) return null;

  const raw = CacheService.getScriptCache().get(key);
  if (!raw) return null;

  try {
    return JSON.parse(raw);
  } catch (error) {
    return null;
  }
}

function putStaffSession_(token, session) {
  const key = staffSessionKey_(token);
  if (!key) throw new Error("Invalid staff session.");

  CacheService.getScriptCache().put(
    key,
    JSON.stringify(session),
    21600,
  );
}

function staffSessionKey_(token) {
  const cleanToken = String(token || "").trim();
  if (!cleanToken) return "";
  return "FIXXIR_STAFF_SESSION_" + staffDigest_(cleanToken);
}

function staffPinHash_(pin, salt) {
  return staffDigest_(
    String(salt || "") +
      "|" +
      String(pin || "") +
      "|" +
      staffAuthPepper_(),
  );
}

function staffAuthPepper_() {
  const props = PropertiesService.getScriptProperties();
  let pepper = props.getProperty("FIXXIR_STAFF_AUTH_PEPPER");

  if (!pepper) {
    pepper = Utilities.getUuid() + Utilities.getUuid();
    props.setProperty("FIXXIR_STAFF_AUTH_PEPPER", pepper);
  }

  return pepper;
}

function staffDigest_(value) {
  const bytes = Utilities.computeDigest(
    Utilities.DigestAlgorithm.SHA_256,
    String(value || ""),
    Utilities.Charset.UTF_8,
  );

  return bytes
    .map((byte) => {
      const n = byte < 0 ? byte + 256 : byte;
      return ("0" + n.toString(16)).slice(-2);
    })
    .join("");
}

function assertScriptOwnerEditor_() {
  const active = String(Session.getActiveUser().getEmail() || "")
    .trim()
    .toLowerCase();

  const effective = String(Session.getEffectiveUser().getEmail() || "")
    .trim()
    .toLowerCase();

  if (!active || !effective || active !== effective) {
    throw new Error(
      "Run this staff-admin function as the Fixxir script owner " +
        "from the Apps Script editor.",
    );
  }

  return active;
}

function adminCreateStaffUser(email, fullName, pin, role) {
  const owner = assertScriptOwnerEditor_();
  ensureStaffAuthSchema_(getSpreadsheet_());

  const normalizedEmail = String(email || "").trim().toLowerCase();
  const name = clean_(fullName);
  const cleanPin = String(pin || "").trim();
  const staffRole = clean_(role) || "Staff";

  if (!normalizedEmail || !normalizedEmail.includes("@")) {
    throw new Error("Enter a valid staff email.");
  }

  if (!name) throw new Error("Staff full name is required.");

  if (!/^\d{4,10}$/.test(cleanPin)) {
    throw new Error("Staff PIN must contain 4 to 10 digits.");
  }

  const existing = getRecords_(FIXXIR.sheets.staffUsers).find(
    (row) =>
      String(row.Email || "").trim().toLowerCase() === normalizedEmail,
  );

  if (existing) {
    throw new Error(
      "A Fixxir staff account already exists for " + normalizedEmail,
    );
  }

  const salt = Utilities.getUuid();
  const id = generateId_(FIXXIR.sheets.staffUsers);

  appendRecord_(FIXXIR.sheets.staffUsers, {
    Staff_ID: id,
    Full_Name: name,
    Email: normalizedEmail,
    PIN_Salt: salt,
    PIN_Hash: staffPinHash_(cleanPin, salt),
    Role: staffRole,
    Status: "Active",
    Created_At: new Date(),
    Created_By: owner,
  });

  return {
    Staff_ID: id,
    Full_Name: name,
    Email: normalizedEmail,
    Role: staffRole,
    Status: "Active",
  };
}

function adminResetStaffPin(email, newPin) {
  assertScriptOwnerEditor_();
  ensureStaffAuthSchema_(getSpreadsheet_());

  const normalizedEmail = String(email || "").trim().toLowerCase();
  const cleanPin = String(newPin || "").trim();

  if (!/^\d{4,10}$/.test(cleanPin)) {
    throw new Error("Staff PIN must contain 4 to 10 digits.");
  }

  const staff = getRecords_(FIXXIR.sheets.staffUsers).find(
    (row) =>
      String(row.Email || "").trim().toLowerCase() === normalizedEmail,
  );

  if (!staff) throw new Error("Staff user not found.");

  const salt = Utilities.getUuid();

  updateRecordById_(
    FIXXIR.sheets.staffUsers,
    "Staff_ID",
    staff.Staff_ID,
    {
      PIN_Salt: salt,
      PIN_Hash: staffPinHash_(cleanPin, salt),
    },
  );

  return true;
}

function adminSetStaffStatus(email, status) {
  assertScriptOwnerEditor_();
  ensureStaffAuthSchema_(getSpreadsheet_());

  const normalizedEmail = String(email || "").trim().toLowerCase();
  const cleanStatus = clean_(status);

  if (!["Active", "Disabled"].includes(cleanStatus)) {
    throw new Error("Status must be Active or Disabled.");
  }

  const staff = getRecords_(FIXXIR.sheets.staffUsers).find(
    (row) =>
      String(row.Email || "").trim().toLowerCase() === normalizedEmail,
  );

  if (!staff) throw new Error("Staff user not found.");

  updateRecordById_(
    FIXXIR.sheets.staffUsers,
    "Staff_ID",
    staff.Staff_ID,
    { Status: cleanStatus },
  );

  return true;
}

function adminListStaffUsers() {
  assertScriptOwnerEditor_();
  ensureStaffAuthSchema_(getSpreadsheet_());

  return getRecords_(FIXXIR.sheets.staffUsers).map((row) => ({
    Staff_ID: row.Staff_ID,
    Full_Name: row.Full_Name,
    Email: row.Email,
    Role: row.Role,
    Status: row.Status,
    Last_Login: row.Last_Login,
  }));
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
