from db_helper import fetch_data, execute_write

def test_database_routing():
    print("STARTING DATABASE ROUTING TEST (READ/WRITE SPLIT)...\n")

    # TEST 1: Testing WRITE flow (Routing to Master)
    print("[TEST 1]: Attempting to WRITE data (Master)...")
    try:
        insert_query = """
        INSERT INTO audit_log (actor, action, detail) 
        VALUES (%s, %s, %s)
        """
        # Secure parameterized input against SQL Injection
        log_id = execute_write(insert_query, ('system_test', 'TEST_ROUTING', 'Testing write routing to Master'))
        print(f"WRITE SUCCESSFUL! Created new log entry with ID = {log_id}\n")
    except Exception as e:
        print(f"WRITE FAILED! Error: {e}\n")

    # TEST 2: Testing READ flow (Routing to Slave)
    print("[TEST 2]: Attempting to READ data (Slave)...")
    try:
        # Retrieve the total number of rooms as per project requirements
        select_query = "SELECT COUNT(*) as total_rooms FROM rooms"
        result = fetch_data(select_query)
        print(f"READ SUCCESSFUL! Result from DB: {result}\n")
    except Exception as e:
        print(f"READ FAILED! Error: {e}\n")

if __name__ == "__main__":
    test_database_routing()