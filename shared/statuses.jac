# Owner: Member A. Case state and coverage are separate concepts.

enum CaseStatus: str {
    DRAFT = "draft",
    PROCESSING = "processing",
    NEEDS_INFORMATION = "needs_information",
    NEEDS_INSPECTION = "needs_inspection",
    COMPLETED = "completed",
    FAILED = "failed"
}

enum StageStatus: str {
    COMPLETED = "completed",
    BLOCKED = "blocked",
    FAILED = "failed"
}

enum CoverageOutcome: str {
    POTENTIALLY_COVERED = "potentially_covered",
    OUTSIDE_PERIOD = "outside_period",
    EXCLUDED_BY_POLICY = "excluded_by_policy",
    NEEDS_REVIEW = "needs_review"
}

glob STAGES: list[str] = ["document", "vision", "coverage", "repair_parts", "resolution"];
glob NEXT_ACTIONS: list[str] = ["continue", "needs_information", "needs_inspection", "complete"];
