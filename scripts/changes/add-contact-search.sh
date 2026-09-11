#!/usr/bin/env bash
set -euo pipefail

CODE_FILE="${1:-Code.js}"
INDEX_FILE="${2:-Index.html}"

for f in "$CODE_FILE" "$INDEX_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: $f not found."
    echo "Run this script from the Fixxir repository root."
    exit 1
  fi
done

if grep -q 'function importContactsCsv' "$CODE_FILE" && \
   grep -q 'function importContactsFile' "$INDEX_FILE"; then
  echo "Contact import/search integration is already installed."
  exit 0
fi

cp "$CODE_FILE" "${CODE_FILE}.before-contact-import.bak"
cp "$INDEX_FILE" "${INDEX_FILE}.before-contact-import.bak"

python3 - "$CODE_FILE" "$INDEX_FILE" <<'PY'
from pathlib import Path
import re
import sys

code_path = Path(sys.argv[1])
index_path = Path(sys.argv[2])

code = code_path.read_text(encoding="utf-8")
html = index_path.read_text(encoding="utf-8")

sheet_anchor = '    settings: "Settings",\n'
if sheet_anchor not in code:
    raise SystemExit('ERROR: Could not find FIXXIR.sheets Settings anchor in Code.js.')

if 'contacts: "Contacts"' not in code:
    code = code.replace(
        sheet_anchor,
        '    contacts: "Contacts",\n' + sheet_anchor,
        1,
    )

config_anchor = '''  closedRepairStatuses: ["Completed", "Cancelled", "Returned Unrepaired"],
});
'''

contact_config = '''  closedRepairStatuses: ["Completed", "Cancelled", "Returned Unrepaired"],
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
'''

if 'FIXXIR_CONTACT_HEADERS' not in code:
    if config_anchor not in code:
        raise SystemExit('ERROR: Could not find FIXXIR config closing anchor in Code.js.')
    code = code.replace(config_anchor, contact_config, 1)

init_anchor = '''  const ss = SpreadsheetApp.openById(id);
  const requiredSheets = Object.values(FIXXIR.sheets);
'''

init_replacement = '''  const ss = SpreadsheetApp.openById(id);

  ensureContactsSheet_(ss);

  const requiredSheets = Object.values(FIXXIR.sheets);
'''

if 'ensureContactsSheet_(ss);' not in code:
    if init_anchor not in code:
        raise SystemExit('ERROR: Could not find initializeFixxir spreadsheet anchor.')
    code = code.replace(init_anchor, init_replacement, 1)

api_anchor = 'function createCustomer(payload) {\n'

contact_api = r'''function importContactsCsv(csvText) {
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

'''

if 'function importContactsCsv' not in code:
    if api_anchor not in code:
        raise SystemExit('ERROR: Could not find createCustomer() anchor in Code.js.')
    code = code.replace(api_anchor, contact_api + api_anchor, 1)

phone_old = '''function normalizePhone_(value) {
  return String(value || "").replace(/\\D/g, "");
}'''

phone_new = '''function normalizePhone_(value) {
  let digits = String(value || "").replace(/\\D/g, "");

  if (digits.startsWith("234") && digits.length >= 13) {
    digits = "0" + digits.slice(3);
  }

  return digits;
}'''

if 'digits.startsWith("234")' not in code:
    if phone_old not in code:
        raise SystemExit('ERROR: Could not safely update normalizePhone_() in Code.js.')
    code = code.replace(phone_old, phone_new, 1)

customer_hidden_anchor = '''            <input type="hidden" name="Customer_ID" id="selectedCustomerId">
          </div>
          <div><label class="required">Customer name</label><input class="input" name="Customer_Name" id="customerName"></div>
          <div><label class="required">Phone</label><input class="input" name="Customer_Phone" id="customerPhone"></div>
          <div><label>Email</label><input class="input" name="Customer_Email"></div>
'''

customer_hidden_replacement = '''            <input type="hidden" name="Customer_ID" id="selectedCustomerId">
            <input type="hidden" name="Customer_Phone_Alternate" id="customerPhoneAlternate">
            <input type="hidden" name="Customer_Address" id="customerAddress">
          </div>
          <div><label class="required">Customer name</label><input class="input" name="Customer_Name" id="customerName"></div>
          <div><label class="required">Phone</label><input class="input" name="Customer_Phone" id="customerPhone"></div>
          <div><label>Email</label><input class="input" name="Customer_Email" id="customerEmail"></div>
'''

if 'id="customerPhoneAlternate"' not in html:
    if customer_hidden_anchor not in html:
        raise SystemExit('ERROR: Could not find New Repair customer fields in Index.html.')
    html = html.replace(customer_hidden_anchor, customer_hidden_replacement, 1)

customers_page_anchor = '''  function renderCustomersPage() {
    document.getElementById('content').innerHTML = `
      <div class="toolbar"><div><h2>Customers</h2><div class="muted" style="margin-top:5px">Find customer history using name, number or ID.</div></div></div>
      <div class="card section"><div class="filters"><input class="input" style="width:min(520px,100%)" id="customerPageQ" placeholder="Search customer…" oninput="debouncedCustomerPageSearch()"></div><div id="customerPageResults" style="margin-top:14px"><div class="empty">Start typing to search.</div></div></div>`;
  }
'''

customers_page_replacement = '''  function renderCustomersPage() {
    document.getElementById('content').innerHTML = `
      <div class="toolbar">
        <div><h2>Customers</h2><div class="muted" style="margin-top:5px">Find customer history using name, number or ID.</div></div>
        <div class="actions">
          <input type="file" id="contactsCsvInput" accept=".csv,text/csv" style="display:none" onchange="importContactsFile(event)">
          <button class="btn" onclick="document.getElementById('contactsCsvInput').click()">Import Contacts CSV</button>
        </div>
      </div>
      <div class="card section"><div class="filters"><input class="input" style="width:min(520px,100%)" id="customerPageQ" placeholder="Search customer…" oninput="debouncedCustomerPageSearch()"></div><div id="customerPageResults" style="margin-top:14px"><div class="empty">Start typing to search.</div></div></div>`;
  }
'''

if 'id="contactsCsvInput"' not in html:
    if customers_page_anchor not in html:
        raise SystemExit('ERROR: Could not find renderCustomersPage() anchor in Index.html.')
    html = html.replace(customers_page_anchor, customers_page_replacement, 1)

finance_anchor = '  function renderFinancePage() {\n'

import_ui = r'''  async function importContactsFile(event){
    const input=event.target;
    const file=input.files&&input.files[0];
    if(!file)return;

    if(!file.name.toLowerCase().endsWith('.csv')){
      toast('Please select the normalized Fixxir contacts CSV.',true);
      input.value='';
      return;
    }

    showLoading(true);
    try{
      const text=await file.text();
      const result=await server('importContactsCsv',text);
      toast(`Imported ${result.imported} contacts`);

      const results=document.getElementById('customerPageResults');
      if(results){
        results.innerHTML=`<div class="empty">${esc(result.imported)} contacts imported. They are now searchable when creating a repair.</div>`;
      }
    }catch(err){
      toast(err.message,true);
    }finally{
      input.value='';
      showLoading(false);
    }
  }

'''

if 'function importContactsFile' not in html:
    if finance_anchor not in html:
        raise SystemExit('ERROR: Could not find renderFinancePage() anchor in Index.html.')
    html = html.replace(finance_anchor, import_ui + finance_anchor, 1)

picker_pattern = re.compile(
    r'''  function debouncedCustomerSearch\(q\)\{clearTimeout\(CUSTOMER_TIMER\);CUSTOMER_TIMER=setTimeout\(\(\)=>searchCustomerPicker\(q\),280\);\}\n  async function searchCustomerPicker\(q\)\{.*?\n  \}\n\n  function selectCustomer\(c\)\{.*?\n  \}\n''',
    re.DOTALL,
)

picker_replacement = r'''  function debouncedCustomerSearch(q){clearTimeout(CUSTOMER_TIMER);CUSTOMER_TIMER=setTimeout(()=>searchCustomerPicker(q),280);}
  async function searchCustomerPicker(q){
    const box=document.getElementById('customerResults');
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

            return `<div class="customer-result" onclick='selectCustomer(${JSON.stringify(c).replace(/'/g,"&#39;")})'>
              <div style="display:flex;align-items:center;justify-content:space-between;gap:8px">
                <b>${esc(c.Full_Name||'Unnamed contact')}</b>
                ${badge}
              </div>
              <span class="muted">${esc(sourceId)} · ${esc(c.Phone_Primary||c.Email||'No phone')}</span>
            </div>`;
          }).join('')
        : '<div class="customer-result muted">No customer or imported contact found — enter details below.</div>';

      box.style.display='block';
    }catch(e){toast(e.message,true)}
  }

  function selectCustomer(c){
    const isExisting=c._Source==='Customer'&&c.Customer_ID;

    document.getElementById('selectedCustomerId').value=isExisting?c.Customer_ID:'';
    document.getElementById('customerName').value=c.Full_Name||'';
    document.getElementById('customerPhone').value=c.Phone_Primary||'';
    document.getElementById('customerPhoneAlternate').value=c.Phone_Alternate||'';
    document.getElementById('customerEmail').value=c.Email||'';
    document.getElementById('customerAddress').value=c.Address||'';

    document.getElementById('selectedCustomer').innerHTML=isExisting
      ? `Using existing customer <b>${esc(c.Full_Name||'')}</b> · ${esc(c.Customer_ID)} · ${esc(c.Phone_Primary||'')}`
      : `Using contact <b>${esc(c.Full_Name||'')}</b> · ${esc(c.Phone_Primary||c.Email||'')}<br><span class="muted">A Fixxir customer record will be created when you create this repair.</span>`;

    document.getElementById('selectedCustomer').style.display='block';
    document.getElementById('customerResults').style.display='none';
  }
'''

if "server('searchCustomerSources',q)" not in html:
    html2, count = picker_pattern.subn(picker_replacement, html, count=1)
    if count != 1:
        raise SystemExit('ERROR: Could not safely replace New Repair customer picker.')
    html = html2

required_code = [
    'contacts: "Contacts"',
    'FIXXIR_CONTACT_HEADERS',
    'function importContactsCsv',
    'function searchCustomerSources',
    'function ensureContactsSheet_',
]
required_html = [
    'id="contactsCsvInput"',
    'function importContactsFile',
    "server('searchCustomerSources',q)",
    'id="customerPhoneAlternate"',
]

missing = [m for m in required_code if m not in code] + [m for m in required_html if m not in html]
if missing:
    raise SystemExit("ERROR: Validation failed. Missing: " + ", ".join(missing))

code_path.write_text(code, encoding="utf-8")
index_path.write_text(html, encoding="utf-8")
PY

echo
echo "Contact import/search integration added."
echo
echo "Review:"
echo "  git diff -- $CODE_FILE $INDEX_FILE"
echo
echo "Then deploy:"
echo "  npm run deploy"
