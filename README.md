# Fixxir Operations MVP — Google Apps Script

This package is the first working internal web-app layer for the Fixxir workbook.

## Included in this MVP

- Operations dashboard
- Repair search/list
- Customer search and automatic customer creation
- New repair intake
- Repair detail view
- Technician assignment field
- Repair financial summary
- Customer payment posting
- Repair expense posting
- Automatic linked Finance_Ledger records
- Automatic linked Repair_Expenses records for repair debits
- Collision-safe sequential IDs using Script Properties + LockService
- Optional email allowlist
- Mobile-responsive interface
- Placeholders for Sales and Inventory (next build phase)

## Required Google Sheet tabs

The code expects the workbook supplied with this package, including:

Customers
Repairs
Repair_Expenses
Technicians
Suppliers
Inventory
Sales_Orders
Sales_Items
Serialized_Devices
Inventory_Movements
Finance_Ledger
Settings

Do not rename those tabs without also changing Code.gs.

## Installation

1. Upload `Fixxir_Operations_Finance_MVP.xlsx` to Google Drive.
2. Open it with Google Sheets and save/convert it as a Google Sheet.
3. Copy the Google Sheet ID from the URL:
   `https://docs.google.com/spreadsheets/d/SHEET_ID/edit`
4. In the Sheet, open **Extensions → Apps Script**.
5. Replace the default `Code.gs` with the supplied `Code.gs`.
6. Create an HTML file named exactly `Index` and paste in `Index.html`.
7. In Apps Script Project Settings, enable **Show "appsscript.json" manifest file in editor**.
8. Replace the manifest with the supplied `appsscript.json`.
9. Save.
10. In `Code.gs`, select/run:
    `initializeFixxir('YOUR_SHEET_ID')`
11. Accept the Google authorization prompts.
12. Optional: run:
    `setAllowedEmails('your@email.com,staff@email.com')`
13. Choose **Deploy → New deployment → Web app**.
14. For the first internal MVP, use deployment access that is restricted to your internal Google accounts/domain wherever your Google account type allows it.
15. Open the Web App URL.

## Important deployment choice

The backend opens the database by Spreadsheet ID rather than depending on an "active spreadsheet" UI context. That makes the deployed web app more predictable.

If you deploy the app to execute as the owner, staff do not need direct access to the raw spreadsheet, depending on your Google account/deployment configuration. Keep the deployment itself restricted to trusted users.

## Finance behavior in this version

A customer repair payment posts one `Credit` row to `Finance_Ledger`, linked with `Repair_ID`.

A repair expense posts one `Debit` row to `Finance_Ledger`, and also mirrors it into `Repair_Expenses` with the generated Finance Transaction ID.

The repair detail calculates:
- Repair value = Final Amount, otherwise Quoted Amount
- Paid = linked Finance credits
- Balance = Repair value - Paid
- Direct costs = linked Finance debits
- Gross profit = Repair value - Direct costs

## Next build phase

1. Full Sales workflow
   - Sales Orders
   - Multiple Sales Items
   - IMEI/serial device selection
   - payment posting
2. Inventory
   - stock-in
   - serialized devices
   - automatic sale-out movement
3. Full Finance Ledger
   - filters/date ranges
   - general expenses
   - cash/bank account views
4. Repair update workflow
   - diagnosis
   - status pipeline
   - QA
   - completion/warranty
5. PDF intake receipt / invoice / sales receipt
6. Roles and permissions
7. Daily closing + management reports
