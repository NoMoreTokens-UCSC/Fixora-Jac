# Owner: Member A. MongoDB is the sole authoritative business store.
import threading;
import from pymongo { MongoClient }
import from shared.config { _get_settings }

glob _client: any = None;
glob _database: any = None;
glob _lock = threading.RLock();

def _get_database() -> any {
    _lock.acquire();
    try {
        if _database is None {
            settings = _get_settings();
            _client = MongoClient(settings.mongodb_uri, serverSelectionTimeoutMS=10000,
                connectTimeoutMS=10000, socketTimeoutMS=15000, appname="fixora-ai");
            candidate = _client[settings.database_name];
            _ensure_indexes(candidate);
            _database = candidate;
        }
        return _database;
    } finally {
        _lock.release();
    }
}

def _ensure_indexes(database: any) {
    database.cases.create_index([("shop_id", 1), ("submission_id", 1)], unique=True);
    database.cases.create_index([("shop_id", 1), ("created_at", -1), ("_id", -1)]);
    database.evidence.create_index([("case_id", 1), ("request_id", 1)], unique=True);
    database.assessments.create_index([("case_id", 1), ("version", 1)], unique=True);
    database.policies.create_index([("shop_id", 1), ("version", 1)], unique=True);
    database.inventory.create_index("sku", unique=True);
}

def _close_connection() {
    _lock.acquire();
    try {
        if _client is not None { _client.close(); }
        _client = None;
        _database = None;
    } finally {
        _lock.release();
    }
}

def _use_test_database(database: any) {
    # Test-only dependency seam; not an API endpoint and never selected by env.
    _close_connection();
    _database = database;
    _ensure_indexes(database);
}
