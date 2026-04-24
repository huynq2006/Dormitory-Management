import streamlit as st
import pandas as pd
import json
import sys
import os

# Add backend directory to system path to import db_helper
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'backend')))

# Import database interaction functions and role configuration 
from db_helper import fetch_rooms, fetch_overdue, generate_monthly_invoices, transfer_student, fetch_current_month_invoices
from roles import ROLES

# Function to load language JSON files
def load_lang(lang_code):
    lang_path = os.path.join(os.path.dirname(__file__), "lang", f"{lang_code}.json")
    with open(lang_path, "r", encoding="utf-8") as f:
        return json.load(f)

# Initialize Session State for language and role if they don't exist
if "lang" not in st.session_state:
    st.session_state["lang"] = "en"  # Default to English
if "role" not in st.session_state:
    st.session_state["role"] = "admin"

# Load current language data
lang = load_lang(st.session_state["lang"])

# SIDEBAR NAVIGATION
st.sidebar.title("Dormitory Management")

# Role Selection Dropdown
role = st.sidebar.selectbox(
    lang["settings"]["role"],
    options=["admin", "manager", "student"],
    format_func=lambda x: lang["roles"][x],
    index=["admin", "manager", "student"].index(st.session_state["role"])
)
st.session_state["role"] = role

# Language Selection Dropdown
lang_code = st.sidebar.selectbox(
    lang["settings"]["language"],
    options=["vi", "en"],
    format_func=lambda x: "Tiếng Việt" if x == "vi" else "English",
    index=["vi", "en"].index(st.session_state["lang"])
)
st.session_state["lang"] = lang_code
lang = load_lang(lang_code)

# Dynamic Menu based on selected Role
pages = ROLES[role]
page_labels = [lang["sidebar"][p] for p in pages]
page = st.sidebar.radio("Menu", pages, format_func=lambda x: lang["sidebar"][x])

# MAIN CONTENT AREA
st.title("Dormitory Management System")

if page == "overview":
    st.header(lang["sidebar"]["overview"])
    st.info("Dashboard content will be displayed here.")

elif page == "rooms":
    # Fallback to fetch title from json, otherwise use sidebar name
    title = lang["rooms"]["title"] if "rooms" in lang and "title" in lang["rooms"] else lang["sidebar"]["rooms"]
    st.header(title)
    try:
        data = fetch_rooms()
        df = pd.DataFrame(data)
        # Display responsive dataframe
        st.dataframe(df, width='stretch')
    except Exception as e:
        st.error(f"Error fetching room list: {e}")

elif page == "overdue":
    st.header(lang["sidebar"]["overdue"])
    try:
        data = fetch_overdue()
        if data:
            # Render data table if there are overdue invoices
            st.dataframe(pd.DataFrame(data), width='stretch')
        else:
            # Display success message if no one is in debt
            st.success("Great! There are no overdue invoices.")
    except Exception as e:
        # English Error Message
        st.error(f"Error fetching overdue data: {e}")

elif page == "invoices":
    st.header(lang["sidebar"]["invoices"])
    st.info("Click the button below to automatically generate invoices for the current month.")
    
    # Primary button to trigger invoice generation
    if st.button("Generate New Invoices", type="primary"):
        try:
            generate_monthly_invoices()
            st.success("Invoices generated successfully!")

            st.write("### Generated Invoices (This Month):")
            data = fetch_current_month_invoices()
            if data:
                st.dataframe(pd.DataFrame(data), width='stretch')
            else:
                st.info("No invoices found for this month.")
        except Exception as e:
            # English Error Message
            st.error(f"Error generating invoices: {e}")

elif page == "transfer":
    st.header(lang["sidebar"]["transfer"])
    
    # Create input form for room transfer
    with st.form("transfer_form"):
        st_id = st.text_input("Enter Student ID:")
        new_room = st.text_input("Enter New Room ID:")
        submitted = st.form_submit_button("Confirm Transfer")
        
        # Action upon form submission
        if submitted:
            if st_id and new_room:
                try:
                    transfer_student(st_id, new_room)
                    st.success(f"Successfully transferred student {st_id} to room {new_room}!")
                except Exception as e:
                    # English Error Message
                    st.error(f"Transaction error: {e}")
            else:
                st.warning("Please fill in all required fields!")


elif page == "sql_workspace":
    st.header(lang["sidebar"]["sql_workspace"])
    st.warning("SQL Workspace: Only available for Admin. (Demo placeholder)")

elif page == "settings":
    st.header(lang["sidebar"]["settings"])
    st.write("Change language and role in the sidebar navigation.")

st.markdown("""
    <style>
    .css-1d391kg {background-color: #f5f6fa;}
    .css-18e3th9 {background-color: #fff;}
    .stSidebar {background-color: #23272f;}
    </style>
""", unsafe_allow_html=True)