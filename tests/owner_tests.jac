import os;
import mongomock;
import from data.connection { _use_test_database, _get_database }
import from shared.validation { _new_id }
import from server.cases { create_case, update_case, get_case }
import from server.owner { owner_message, owner_review, owner_inspection }

glob OWNER_TOKEN: str = "owner-test-service-token";

def _owner_case(completed: bool = False) -> dict[str, any] {
    os.environ["FIXORA_MONGODB_URI"] = "mongodb://localhost";
    os.environ["FIXORA_ACCESS_TOKEN"] = OWNER_TOKEN;
    _use_test_database(mongomock.MongoClient()["owner_tests"]);
    created = create_case(description="Cracked display", submission_id=_new_id(), access_token=OWNER_TOKEN);
    assert created.ok;
    item = created.data["case"] as dict[str, any];
    if completed {
        aid = _new_id();
        _get_database().cases.update_one({"_id": item["id"]}, {"$set": {"status": "completed", "active_assessment_id": aid,
            "assessment": {"_id": aid, "case_id": item["id"], "version": 1, "request_id": _new_id(), "stages": {}, "next_stage": 5}}});
        return get_case(case_id=item["id"] as str, access_token=OWNER_TOKEN).data["case"] as dict[str, any];
    }
    return item;
}

test "owner operations require the service token" {
    item = _owner_case();
    result = owner_message(case_id=item["id"] as str, expected_revision=0, text="Private", request_id=_new_id(), access_token="wrong");
    assert not result.ok and result.error.code == "UNAUTHORIZED";
}

test "final review requires completed assessment and current revision" {
    item = _owner_case();
    result = owner_review(case_id=item["id"] as str, expected_revision=0, action="approved", reason="Checked", request_id=_new_id(), access_token=OWNER_TOKEN);
    assert not result.ok and result.error.code == "INVALID_STATE";
    item = _owner_case(True);
    result = owner_review(case_id=item["id"] as str, expected_revision=1, action="approved", reason="Checked", request_id=_new_id(), access_token=OWNER_TOKEN);
    assert not result.ok and result.error.code == "STALE_REVISION";
}

test "owner review is separate from assessment and invalidated by correction" {
    item = _owner_case(True);
    result = owner_review(case_id=item["id"] as str, expected_revision=0, action="approved", reason="Shop confirms proposal", request_id=_new_id(), access_token=OWNER_TOKEN);
    assert result.ok;
    item = result.data["case"] as dict[str, any];
    assert item["status"] == "completed" and item["review_status"] == "approved";
    assert item["review_assessment_id"] == item["active_assessment_id"];
    assert len(item["decisions"]) == 1 and item["messages"][0]["publication_pending"];
    corrected = update_case(case_id=item["id"] as str, expected_revision=item["revision"] as int,
        description="Corrected complaint", access_token=OWNER_TOKEN);
    assert corrected.ok;
    item = corrected.data["case"] as dict[str, any];
    assert item["review_status"] == "unreviewed" and item["assessment"] is None;
    assert len(item["decisions"]) == 1;
}

test "requesting information blocks approval until a new assessment" {
    item = _owner_case(True);
    requested = owner_review(case_id=item["id"] as str, expected_revision=0, action="needs_information",
        reason="Confirm serial number", request_id=_new_id(), access_token=OWNER_TOKEN);
    assert requested.ok;
    result = owner_review(case_id=item["id"] as str, expected_revision=1, action="approved",
        reason="Bypass missing details", request_id=_new_id(), access_token=OWNER_TOKEN);
    assert not result.ok and result.error.code == "INVALID_STATE";
}

test "private owner notes are not marked for WhatsApp publication" {
    item = _owner_case(); rid = _new_id();
    for attempt in range(2) {
        result = owner_message(case_id=item["id"] as str, expected_revision=0, text="Internal diagnostic note",
            internal=True, request_id=rid, access_token=OWNER_TOKEN);
        assert result.ok;
    }
    messages = result.data["case"]["messages"];
    assert len(messages) == 1 and messages[0]["internal"] and not messages[0]["publication_pending"];
}

test "inspection creates a revision and archives assessment without sending private findings" {
    item = _owner_case(True);
    result = owner_inspection(case_id=item["id"] as str, expected_revision=0, diagnosis_code="screen_crack",
        notes="Physically inspected display", request_id=_new_id(), access_token=OWNER_TOKEN);
    assert result.ok;
    item = result.data["case"] as dict[str, any];
    assert item["revision"] == 1 and item["status"] == "draft" and item["assessment"] is None;
    assert item["owner_inspection"]["diagnosis_code"] == "screen_crack";
    assert item["messages"][0]["internal"] and not item["messages"][0]["publication_pending"];
    assert _get_database().assessments.count_documents({}) == 1;
}

test "unsupported inspection diagnoses cannot enter the workflow" {
    item = _owner_case();
    result = owner_inspection(case_id=item["id"] as str, expected_revision=0, diagnosis_code="invented_battery_fault",
        notes="Unverified", request_id=_new_id(), access_token=OWNER_TOKEN);
    assert not result.ok and result.error.code == "VALIDATION_ERROR";
}
