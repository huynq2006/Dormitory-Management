import streamlit as st
import pandas as pd
import json
import sys
import os

# Add backend directory to system path to import db_helper
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'backend')))

# Import database interaction functions and role configuration 
from db_helper import fetch_rooms, fetch_overdue, generate_monthly_invoices, transfer_student, fetch_current_month_invoices, fetch_data, execute_write, fetch_student_info, fetch_inactive_students, assign_room_to_student
from roles import ROLES

# Function to load language JSON files
def load_lang(lang_code):
    lang_path = os.path.join(os.path.dirname(__file__), "lang", f"{lang_code}.json")
    with open(lang_path, "r", encoding="utf-8") as f:
        return json.load(f)

# Initialize Session State for language, role and current page if they don't exist
if "lang" not in st.session_state:
    st.session_state["lang"] = "en"  # Default to English
if "role" not in st.session_state:
    st.session_state["role"] = "admin"
if "page" not in st.session_state:
    st.session_state["page"] = "rooms"

# Load current language data
lang = load_lang(st.session_state["lang"])

# SIDEBAR NAVIGATION
st.sidebar.title("Dormitory Management")

# Language Selection Dropdown
lang_code = st.sidebar.selectbox(
    lang["settings"]["language"],
    options=["vi", "en"],
    format_func=lambda x: "Tiếng Việt" if x == "vi" else "English",
    index=["vi", "en"].index(st.session_state["lang"])
)
st.session_state["lang"] = lang_code
lang = load_lang(lang_code)

# Role Selection Dropdown
role = st.sidebar.selectbox(
    lang["settings"]["role"],
    options=["admin", "manager", "student"],
    format_func=lambda x: lang["roles"][x],
    index=["admin", "manager", "student"].index(st.session_state["role"])
)
st.session_state["role"] = role

# Dynamic Menu based on selected Role
pages = ROLES[role]

# Pre-flight: if saved page is not in this role's menu, reset it BEFORE the widget renders
if st.session_state["page"] not in pages:
    st.session_state["page"] = pages[0]

# key="page" tells Streamlit to auto-sync the radio with session_state["page"]
# This eliminates the need for index= and avoids the two-click lag bug
page = st.sidebar.radio(
    "Menu",
    pages,
    format_func=lambda x: lang["sidebar"][x],
    key="page"
)

# MAIN CONTENT AREA
st.title("Dormitory Management System")

if page == "rooms":
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
    
    # Double check security: Only Admin can access
    if st.session_state["role"] == "admin":
        st.info("Admin Area: Execute raw SQL queries directly on the database.")
        
        # SQL Input Area
        sql_query = st.text_area("Enter SQL Query:", height=150, placeholder="SELECT * FROM rooms LIMIT 10;")
        
        if st.button("Execute Query", type="primary"):
            if not sql_query.strip():
                st.warning("Please enter a SQL query before executing.")
            else:
                # Classify query type (Read vs Write)
                query_upper = sql_query.strip().upper()
                try:
                    if query_upper.startswith("SELECT") or query_upper.startswith("SHOW"):
                        # Handle Read queries
                        result = fetch_data(sql_query)
                        if result:
                            st.success("Query executed successfully!")
                            st.dataframe(pd.DataFrame(result), width='stretch')
                        else:
                            st.info("Query executed successfully, but no data was returned.")
                    else:
                        # Handle Write queries (INSERT, UPDATE, DELETE, etc.)
                        # Note: execute_write should ideally support raw queries without tuple params if passed None
                        execute_write(sql_query, params=None)
                        st.success("Database modified successfully!")
                        
                except Exception as e:
                    st.error(f"SQL Execution Error: {e}")
    else:
        # Fallback security message if a non-admin bypasses the menu
        st.error("Access Denied: You do not have permission to view this workspace.")

elif page == "student_info":
    st.header(lang["student_info"]["title"])
    
    # Search form for student info
    with st.form("student_search_form"):
        student_code = st.text_input(lang["student_info"]["input_label"])
        search_submitted = st.form_submit_button(lang["student_info"]["button"])
        
        if search_submitted:
            if student_code:
                try:
                    data = fetch_student_info(student_code)
                    if data:
                        st.success(f"Found {len(data)} record(s) for {student_code}")
                        for idx, record in enumerate(data):
                            if len(data) > 1:
                                st.subheader(f"{lang['student_info']['contract_id']}: {record['contract_id']}")
                            
                            # Map gender code to label
                            gender_label = lang["student_info"].get(f"gender_{record['gender'].lower()}", record['gender'])
                            
                            # Display information vertically
                            st.markdown(f"**{lang['student_info']['full_name']}:** {record['full_name']}")
                            st.markdown(f"**{lang['student_info']['gender']}:** {gender_label}")
                            st.markdown(f"**{lang['student_info']['email']}:** {record['email']}")
                            st.markdown(f"**{lang['student_info']['phone']}:** {record['phone']}")
                            st.markdown(f"**{lang['student_info']['contract_id']}:** {record['contract_id']}")
                            st.markdown(f"**{lang['student_info']['room_id']}:** {record['room_id']}")
                            st.markdown(f"**{lang['student_info']['building']}:** {record['building'] if record['building'] else 'N/A'}")
                            st.markdown(f"**{lang['student_info']['start_date']}:** {record['start_date']}")
                            st.markdown(f"**{lang['student_info']['end_date']}:** {record['end_date'] if record['end_date'] else 'N/A'}")
                            st.markdown(f"**{lang['student_info']['contract_status']}:** {record['contract_status']}")
                            
                            if idx < len(data) - 1:
                                st.divider()
                    else:
                        st.warning(lang["student_info"]["not_found"])
                except Exception as e:
                    st.error(f"Error: {e}")
            else:
                st.warning("Please enter a student code.")



elif page == "waiting_list":
    st.header(lang["waiting_list"]["title"])

    # ---------- Inactive student table ----------
    try:
        data = fetch_inactive_students()
        if data:
            df = pd.DataFrame(data)
            # Rename columns using lang keys if available
            col_map = {
                "student_id":   lang["waiting_list"].get("col_student_id", "student_id"),
                "student_code": lang["waiting_list"].get("col_student_code", "student_code"),
                "full_name":    lang["waiting_list"].get("col_full_name", "full_name"),
                "gender":       lang["waiting_list"].get("col_gender", "gender"),
                "email":        lang["waiting_list"].get("col_email", "email"),
                "phone":        lang["waiting_list"].get("col_phone", "phone"),
                "status":       lang["waiting_list"].get("col_status", "status"),
            }
            df.rename(columns={k: v for k, v in col_map.items() if k in df.columns}, inplace=True)
            st.dataframe(df, use_container_width=True)
        else:
            st.success(lang["waiting_list"]["no_students"])
    except Exception as e:
        st.error(f"Error fetching waiting list: {e}")

    # ---------- Assign-room form (admin & manager only) ----------
    if st.session_state["role"] in ("admin", "manager"):
        st.divider()
        st.subheader(lang["waiting_list"]["assign_title"])
        st.info(lang["waiting_list"]["assign_info"])

        with st.form("assign_room_form"):
            col1, col2 = st.columns(2)
            with col1:
                assign_student_id = st.text_input(
                    lang["waiting_list"]["assign_student_id"],
                    placeholder="e.g. 42"
                )
            with col2:
                assign_room_id = st.text_input(
                    lang["waiting_list"]["assign_room_id"],
                    placeholder="e.g. 5"
                )
            submitted = st.form_submit_button(
                lang["waiting_list"]["assign_button"],
                type="primary"
            )

            if submitted:
                if assign_student_id and assign_room_id:
                    try:
                        assign_room_to_student(
                            int(assign_student_id),
                            int(assign_room_id)
                        )
                        st.success(
                            lang["waiting_list"]["assign_success"]
                            .format(sid=assign_student_id, rid=assign_room_id)
                        )
                        st.rerun()
                    except ValueError:
                        st.error(lang["waiting_list"]["assign_invalid_id"])
                    except Exception as e:
                        st.error(f"{lang['waiting_list']['assign_error']}: {e}")
                else:
                    st.warning(lang["waiting_list"]["assign_missing_fields"])

st.markdown("""
    <style>
    .css-1d391kg {color: black;}
    .css-18e3th9 {color: black;}
    </style>
""", unsafe_allow_html=True)