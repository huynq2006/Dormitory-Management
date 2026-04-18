import streamlit as st
import pandas as pd
import json
import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'backend')))
from db_helper import fetch_rooms
from roles import ROLES

# Load language files
def load_lang(lang_code):
    lang_path = os.path.join(os.path.dirname(__file__), "lang", f"{lang_code}.json")
    with open(lang_path, "r", encoding="utf-8") as f:
        return json.load(f)

# Session state for language and role
if "lang" not in st.session_state:
    st.session_state["lang"] = "vi"
if "role" not in st.session_state:
    st.session_state["role"] = "admin"

lang = load_lang(st.session_state["lang"])

# Sidebar
st.sidebar.title("Dormitory Management")
role = st.sidebar.selectbox(
    lang["settings"]["role"],
    options=["admin", "manager", "student"],
    format_func=lambda x: lang["roles"][x],
    index=["admin", "manager", "student"].index(st.session_state["role"])
)
st.session_state["role"] = role

lang_code = st.sidebar.selectbox(
    lang["settings"]["language"],
    options=["vi", "en"],
    format_func=lambda x: "Tiếng Việt" if x == "vi" else "English",
    index=["vi", "en"].index(st.session_state["lang"])
)
st.session_state["lang"] = lang_code
lang = load_lang(lang_code)

# Sidebar navigation
pages = ROLES[role]
page_labels = [lang["sidebar"][p] for p in pages]
page = st.sidebar.radio("Menu", pages, format_func=lambda x: lang["sidebar"][x])

# Main content
st.title("Dormitory Management System")

if page == "overview":
    st.header(lang["sidebar"]["overview"])
    st.info("Dashboard content here")
elif page == "rooms":
    st.header(lang["rooms"]["title"])
    try:
        data = fetch_rooms()
        df = pd.DataFrame(data)
        st.dataframe(df, use_container_width=True)
    except Exception as e:
        st.error(f"Error fetching rooms: {e}")
elif page == "sql_workspace":
    st.header(lang["sidebar"]["sql_workspace"])
    st.warning("SQL Workspace: Only available for Admin. (Demo placeholder)")
elif page == "settings":
    st.header(lang["sidebar"]["settings"])
    st.write("Change language and role in the sidebar.")

# Custom CSS for corporate style (optional)
st.markdown("""
    <style>
    .css-1d391kg {background-color: #f5f6fa;}
    .css-18e3th9 {background-color: #fff;}
    .stSidebar {background-color: #23272f;}
    </style>
""", unsafe_allow_html=True)