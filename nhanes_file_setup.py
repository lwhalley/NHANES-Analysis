"""
Downloads XPT files from the CDC website and loads them into a 
SQLite database.


Output:
    nhanes_2021_2023.db  — open this file in DB Browser for SQLite
    /data/               — raw XPT files (cached locally so re-runs are fast)
"""

import os
import sqlite3
import requests
import pandas as pd

# ── Configuration ────────────────────────────────────────────────────────────

BASE_URL = "https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2021/DataFiles/"
DATA_DIR = "./data"
DB_PATH  = "nhanes_2021_2023.db"

os.makedirs(DATA_DIR, exist_ok=True)

# ── Files to Download ────────────────────────────────────────────────────────
# Organized by component. Each entry is (xpt_filename, sql_table_name, description)

FILES = [

    # --- DEMOGRAPHICS ---
    # Core respondent info: age, sex, race, income, education, sample weights
    ("DEMO_L.xpt",      "demographics",         "Demographics & Sample Weights"),

    # --- DIETARY ---
    # 24-hour dietary recall: detailed nutrient intake per respondent (Day 1)
    ("DR1TOT_L.xpt",    "dietary_total_day1",   "Dietary Recall - Total Nutrients, Day 1"),
    # Day 2 recall (subset of respondents) — optional, adds statistical power
    ("DR2TOT_L.xpt",    "dietary_total_day2",   "Dietary Recall - Total Nutrients, Day 2"),

    # --- EXAMINATION ---
    # Physical measurements: height, weight, BMI, waist circumference
    ("BMX_L.xpt",       "body_measures",        "Body Measures (BMI, Weight, Height)"),
    # Blood pressure readings (average of multiple measurements)
    ("BPXO_L.xpt",      "blood_pressure",       "Blood Pressure"),

    # --- LABORATORY ---
    # Blood glucose (fasting) — key diabetes/prediabetes marker
    ("GLU_L.xpt",       "glucose",              "Fasting Glucose"),
    # HbA1c — long-term glycemic control
    ("GHB_L.xpt",       "hba1c",                "Glycohemoglobin (HbA1c)"),
    # Insulin — insulin resistance marker
    ("INS_L.xpt",       "insulin",              "Fasting Insulin"),
    # Complete blood count — anemia, iron status indicators
    ("CBC_L.xpt",       "cbc",                  "Complete Blood Count"),
    # Ferritin — iron storage marker
    ("FERTIN_L.xpt",    "ferritin",             "Ferritin"),
    # Transferrin receptor — functional iron deficiency
    ("TFR_L.xpt",       "transferrin",          "Transferrin Receptor"),
    # Vitamin D — widespread deficiency, metabolic implications
    ("VID_L.xpt",       "vitamin_d",            "Vitamin D (25-OH)"),
    # Folate & B12 — nutrient deficiency markers
    ("FOLFMS_L.xpt",    "folate_b12",           "Folate & B12"),
    # Cholesterol panel (total, HDL, LDL, triglycerides)
    ("TCHOL_L.xpt",     "cholesterol_total",    "Total Cholesterol"),
    ("HDL_L.xpt",       "cholesterol_hdl",      "HDL Cholesterol"),
    ("TRIGLY_L.xpt",    "cholesterol_trigly",   "Triglycerides & LDL"),

    # --- QUESTIONNAIRE ---
    # Diabetes diagnosis, treatment, awareness
    ("DIQ_L.xpt",       "diabetes",             "Diabetes Questionnaire"),
    # Blood pressure & cholesterol diagnosis/treatment
    ("BPQ_L.xpt",       "bp_cholesterol_q",     "Blood Pressure & Cholesterol Questionnaire"),
    # Medical conditions (heart disease, stroke, cancer, thyroid, etc.)
    ("MCQ_L.xpt",       "medical_conditions",   "Medical Conditions"),
    # Physical activity (moderate, vigorous, sedentary behavior)
    ("PAQ_L.xpt",       "physical_activity",    "Physical Activity"),
    # Health insurance coverage
    ("HIQ_L.xpt",       "insurance",            "Health Insurance"),
    # Healthcare utilization (doctor visits, hospital stays, ER visits)
    ("HUQ_L.xpt",       "healthcare_util",      "Healthcare Utilization"),
    # Prescription medications
    ("RXQ_RX_L.xpt",    "medications",          "Prescription Medications"),
    # Weight history & weight loss attempts
    ("WHQ_L.xpt",       "weight_history",       "Weight History"),
    # Food security
    ("FSQ_L.xpt",       "food_security",        "Food Security"),
    # Sleep disorders
    ("SLQ_L.xpt",       "sleep",                "Sleep Disorders"),
    # Kidney conditions (relevant to dietary protein/electrolytes)
    ("KIQ_U_L.xpt",     "kidney",               "Kidney Conditions"),
]

# ── Helper Functions ─────────────────────────────────────────────────────────

def _looks_like_html_error(path: str) -> bool:
    """
    Quick heuristic to detect when a cached '.xpt' file is actually an HTML
    error page (e.g., CDC 'Page Not Found'), which will cause parsing to fail.
    """
    try:
        with open(path, "rb") as f:
            head = f.read(1024).decode("utf-8", errors="ignore")
        return "<!DOCTYPE html" in head and "Page Not Found" in head
    except OSError:
        return False


def download_xpt(filename):
    """Download an XPT file from CDC if not already cached locally."""
    local_path = os.path.join(DATA_DIR, filename)

    # If a cached file exists but is actually an HTML error page from a previous
    # bad URL, delete it and force a fresh download.
    if os.path.exists(local_path):
        if _looks_like_html_error(local_path):
            print(f"  [re-download] {filename} (cached HTML error page)")
            try:
                os.remove(local_path)
            except OSError:
                pass
        else:
            print(f"  [cached]    {filename}")
            return local_path

    url = BASE_URL + filename
    print(f"  [download]  {filename} ... ", end="", flush=True)
    response = requests.get(url, timeout=60)
    if response.status_code == 200:
        with open(local_path, "wb") as f:
            f.write(response.content)

        # Guard against the server returning an HTML error page with status 200.
        if _looks_like_html_error(local_path):
            print("FAILED (received HTML error page)")
            try:
                os.remove(local_path)
            except OSError:
                pass
            return None

        print("done")
        return local_path
    else:
        print(f"FAILED (HTTP {response.status_code})")
        return None


def xpt_to_dataframe(xpt_path):
    """Read an XPT file into a pandas DataFrame."""
    try:
        df = pd.read_sas(xpt_path, format="xport", encoding="utf-8")
        # Normalize column names to lowercase for easier SQL
        df.columns = [c.lower() for c in df.columns]
        return df
    except Exception as e:
        print(f"    WARNING: Could not read {xpt_path}: {e}")
        return None


def load_to_sqlite(conn, df, table_name):
    """Load a DataFrame into SQLite, replacing any existing table."""
    df.to_sql(table_name, conn, if_exists="replace", index=False)
    cursor = conn.execute(f"SELECT COUNT(*) FROM {table_name}")
    row_count = cursor.fetchone()[0]
    print(f"    → loaded {row_count:,} rows into '{table_name}'")


# ── Main Pipeline ────────────────────────────────────────────────────────────

def main():
    print("=" * 60)
    print("NHANES 2021-2023 Data Pipeline")
    print("=" * 60)
    print(f"Database will be saved to: {DB_PATH}")
    print("Open this file in DB Browser for SQLite when complete.\n")

    conn = sqlite3.connect(DB_PATH)
    loaded = []
    failed = []

    for xpt_filename, table_name, description in FILES:
        print(f"\n[{description}]")

        # 1. Download
        xpt_path = download_xpt(xpt_filename)
        if xpt_path is None:
            failed.append((xpt_filename, "download failed"))
            continue

        # 2. Parse
        df = xpt_to_dataframe(xpt_path)
        if df is None:
            failed.append((xpt_filename, "parse failed"))
            continue

        # 3. Load
        load_to_sqlite(conn, df, table_name)
        loaded.append(table_name)

    conn.close()