#!/usr/bin/env bash
set -euo pipefail

CODE_FILE="${1:-Code.js}"
INDEX_FILE="${2:-Index.html}"
MANIFEST_FILE="${3:-appsscript.json}"

for f in "$CODE_FILE" "$INDEX_FILE" "$MANIFEST_FILE"; do
  [[ -f "$f" ]] || { echo "ERROR: $f not found."; exit 1; }
done

if grep -q 'FIXXIR_STAFF_AUTH_V1' "$CODE_FILE" && grep -q 'FIXXIR_STAFF_AUTH_UI_V1' "$INDEX_FILE"; then
  echo "Fixxir staff-auth patch is already installed."
  exit 0
fi

cp "$CODE_FILE" "${CODE_FILE}.before-staff-auth-v1.bak"
cp "$INDEX_FILE" "${INDEX_FILE}.before-staff-auth-v1.bak"
cp "$MANIFEST_FILE" "${MANIFEST_FILE}.before-staff-auth-v1.bak"

python3 - "$CODE_FILE" "$INDEX_FILE" "$MANIFEST_FILE" <<'PY'
from pathlib import Path
import json, re, sys

code_path = Path(sys.argv[1])
html_path = Path(sys.argv[2])
manifest_path = Path(sys.argv[3])

code = code_path.read_text(encoding="utf-8")
html = html_path.read_text(encoding="utf-8")

def fail(msg):
    raise SystemExit("ERROR: " + msg)

# Manifest: execute as Fixxir/deployer so staff do not need Sheet access.
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
webapp = manifest.setdefault("webapp", {})
webapp["executeAs"] = "USER_DEPLOYING"
webapp.setdefault("access", "ANYONE")
manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

# Register Staff_Users sheet and IDs.
if 'staffUsers: "Staff_Users"' not in code:
    anchor = '    customers: "Customers",\n'
    if anchor not in code:
        anchor = '    settings: "Settings",\n'
    if anchor not in code:
        fail("Could not locate FIXXIR.sheets.")
    code = code.replace(anchor, anchor + '    staffUsers: "Staff_Users",\n', 1)

if 'Staff_Users: "STF"' not in code:
    anchor = '    Customers: "CUS",\n'
    if anchor not in code:
        anchor = '    Finance_Ledger: "TXN",\n'
    if anchor not in code:
        fail("Could not locate FIXXIR prefixes.")
    code = code.replace(anchor, anchor + '    Staff_Users: "STF",\n', 1)

if "const FIXXIR_STAFF_USER_HEADERS" not in code:
    pos = code.find("function doGet()")
    if pos < 0:
        fail("Could not locate doGet().")

    code = code[:pos] + r'''
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

''' + code[pos:]

# Ensure Staff_Users exists before required-sheet validation.
if "ensureStaffAuthSchema_(ss);" not in code:
    anchor = "  const requiredSheets = Object.values(FIXXIR.sheets);\n"
    if anchor not in code:
        fail("Could not locate initializeFixxir requiredSheets.")
    code = code.replace(anchor, "  ensureStaffAuthSchema_(ss);\n\n" + anchor, 1)

# Replace old Google-session authorization with internal staff session auth.
auth_start = code.find("function assertAuthorized_()")
require_fields = code.find("function requireFields_", auth_start)
if auth_start < 0 or require_fields < 0:
    fail("Could not locate authorization helpers.")

code = code[:auth_start] + r'''function assertAuthorized_() {
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

''' + code[require_fields:]

# Insert staff-auth backend.
if "function loginStaff(email, pin)" not in code:
    pos = code.find("function requireFields_")
    if pos < 0:
        fail("Could not locate helper insertion point.")

    backend = r'''/* ---------------- Internal Staff Authentication ---------------- */

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

'''
    code = code[:pos] + backend + code[pos:]

# Frontend login modal.
if 'id="staffLoginModal"' not in html:
    pos = html.find('<div class="toast" id="toast"></div>')
    if pos < 0:
        fail("Could not locate toast insertion point.")

    html = html[:pos] + r'''<div class="modal" id="staffLoginModal">
  <div class="modal-box" style="width:min(480px,100%)">
    <div class="modal-head"><h3>Fixxir Staff Login</h3></div>
    <form id="staffLoginForm" onsubmit="submitStaffLogin(event)">
      <div class="modal-body">
        <div class="form-grid" style="grid-template-columns:1fr">
          <div>
            <label class="required">Staff email</label>
            <input class="input" type="email" id="staffLoginEmail" autocomplete="username" required />
          </div>
          <div>
            <label class="required">PIN</label>
            <input class="input" type="password" inputmode="numeric" pattern="[0-9]{4,10}" id="staffLoginPin" autocomplete="current-password" required />
          </div>
        </div>
        <div class="muted" style="font-size:12px;margin-top:12px">Use the email and PIN assigned to you by Fixxir.</div>
        <div id="staffLoginError" style="display:none;margin-top:12px;color:#b42318;font-weight:700"></div>
      </div>
      <div class="modal-foot"><button class="btn primary" type="submit">Sign in</button></div>
    </form>
  </div>
</div>

''' + html[pos:]

# Frontend state.
anchor = "      let BOOT = null;\n"
if anchor not in html:
    fail("Could not locate BOOT global.")

if "let STAFF_TOKEN" not in html:
    html = html.replace(
        anchor,
        '''      let STAFF_TOKEN =
        localStorage.getItem("fixxir_staff_token") || "";
      let STAFF_USER = null;
''' + anchor,
        1,
    )

# Replace startup + server wrapper.
load_start = html.find('window.addEventListener("load", async () => {')
server_start = html.find("      function server(fn, arg) {", load_start)
navigate_start = html.find("      function navigate(page, el) {", server_start)

if load_start < 0 or server_start < 0 or navigate_start < 0:
    fail("Could not locate startup/server wrapper.")

startup = r'''window.addEventListener("load", async () => {
        await startFixxirApp();
      });

      async function startFixxirApp() {
        showLoading(true);

        try {
          if (!STAFF_TOKEN) {
            showStaffLogin();
            return;
          }

          try {
            const resumed = await authServer(
              "resumeStaffSession",
              STAFF_TOKEN,
            );
            STAFF_USER = resumed.user || null;
          } catch (error) {
            clearStaffSession();
            showStaffLogin();
            return;
          }

          await loadAuthenticatedFixxir();
        } finally {
          showLoading(false);
        }
      }

      async function loadAuthenticatedFixxir() {
        BOOT = await server("getBootstrapData");

        document.getElementById("userLabel").textContent =
          STAFF_USER?.fullName ||
          BOOT.user ||
          "";

        populateStaticSelects();
        renderDashboard(BOOT.dashboard);
      }

      function showStaffLogin(message) {
        const errorBox = document.getElementById("staffLoginError");

        if (errorBox) {
          errorBox.textContent = message || "";
          errorBox.style.display = message ? "block" : "none";
        }

        document.getElementById("staffLoginModal")?.classList.add("open");

        setTimeout(() => {
          document.getElementById("staffLoginEmail")?.focus();
        }, 50);
      }

      async function submitStaffLogin(event) {
        event.preventDefault();

        const email =
          document.getElementById("staffLoginEmail")?.value || "";
        const pin =
          document.getElementById("staffLoginPin")?.value || "";

        showLoading(true);

        try {
          const result = await authServer(
            "loginStaff",
            email,
            pin,
          );

          STAFF_TOKEN = result.token;
          STAFF_USER = result.user || null;

          localStorage.setItem("fixxir_staff_token", STAFF_TOKEN);

          closeModal("staffLoginModal");
          await loadAuthenticatedFixxir();
        } catch (error) {
          showStaffLogin(error.message || "Unable to sign in.");
        } finally {
          showLoading(false);
        }
      }

      async function signOutStaff() {
        const oldToken = STAFF_TOKEN;
        clearStaffSession();

        if (oldToken) {
          try {
            await authServer("logoutStaff", oldToken);
          } catch (error) {}
        }

        BOOT = null;
        STAFF_USER = null;
        showStaffLogin();
      }

      function clearStaffSession() {
        STAFF_TOKEN = "";
        STAFF_USER = null;
        localStorage.removeItem("fixxir_staff_token");
      }

      function authServer(fn, ...args) {
        return new Promise((resolve, reject) => {
          const runner = google.script.run
            .withSuccessHandler(resolve)
            .withFailureHandler((err) =>
              reject(
                new Error(
                  err && err.message
                    ? err.message
                    : String(err),
                ),
              ),
            );

          runner[fn](...args);
        });
      }

      function server(fn, arg) {
        return new Promise((resolve, reject) => {
          const runner = google.script.run
            .withSuccessHandler(resolve)
            .withFailureHandler((err) => {
              const message =
                err && err.message
                  ? err.message
                  : String(err);

              if (message.includes("STAFF_SESSION_EXPIRED")) {
                clearStaffSession();
                showStaffLogin(
                  "Your Fixxir session expired. Sign in again.",
                );
              }

              reject(new Error(message));
            });

          runner.invokeWithStaffSession(
            fn,
            arg !== undefined,
            arg === undefined ? null : arg,
            STAFF_TOKEN,
          );
        });
      }

      '''

html = html[:load_start] + startup + html[navigate_start:]

# Add sign-out button next to user label if possible.
script_pos = html.find("<script>")
if "onclick=\"signOutStaff()\"" not in html[:script_pos]:
    match = re.search(
        r'''(?is)(<[^>]+\bid=["']userLabel["'][^>]*></[^>]+>)''',
        html[:script_pos],
    )
    if match:
        html = (
            html[:match.start()]
            + match.group(1)
            + ' <button class="btn small" onclick="signOutStaff()">Sign out</button>'
            + html[match.end():]
        )

if "FIXXIR_STAFF_AUTH_UI_V1" not in html:
    html = html.replace(
        "</style>",
        "  /* FIXXIR_STAFF_AUTH_UI_V1 */\n  </style>",
        1,
    )

# Validation.
for needle in [
    "FIXXIR_STAFF_AUTH_V1",
    'staffUsers: "Staff_Users"',
    "function loginStaff(email, pin)",
    "function invokeWithStaffSession(",
    "function adminCreateStaffUser(",
    "function requireRuntimeStaff_()",
]:
    if needle not in code:
        fail("Missing backend marker: " + needle)

for needle in [
    "FIXXIR_STAFF_AUTH_UI_V1",
    'id="staffLoginModal"',
    "function submitStaffLogin(event)",
    "function authServer(fn, ...args)",
    "runner.invokeWithStaffSession(",
]:
    if needle not in html:
        fail("Missing frontend marker: " + needle)

code_path.write_text(code, encoding="utf-8")
html_path.write_text(html, encoding="utf-8")
PY

echo
echo "======================================================"
echo " Fixxir private-database staff login installed"
echo "======================================================"
echo
echo "Review:"
echo "  git diff --check"
echo "  git diff -- Code.js Index.html appsscript.json"
echo
echo "Then deploy:"
echo "  npm run deploy"
echo
echo "Create staff accounts from the Apps Script editor:"
echo '  adminCreateStaffUser("staff@gmail.com", "Staff Name", "482913", "Staff")'
echo
echo "Other owner commands:"
echo '  adminListStaffUsers()'
echo '  adminResetStaffPin("staff@gmail.com", "927461")'
echo '  adminSetStaffStatus("staff@gmail.com", "Disabled")'
echo
echo "Staff no longer need direct access to the Google Sheet."
echo "Audit fields record the logged-in Fixxir staff email."
