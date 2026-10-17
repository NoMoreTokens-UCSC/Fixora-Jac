# Owner: Member A. Request-local graph; never attached to persistent root.
import from shared.statuses { STAGES }

node CaseGraph {
    has case_id: str;
    has next_ordinal: int;
}

node StageNode {
    has name: str;
    has ordinal: int;
}

edge HasStage: CaseGraph --> StageNode {}

walker SelectNextStage {
    has selected: str = "";
    has target_ordinal: int = 0;

    can enter_case with CaseGraph entry {
        self.target_ordinal = here.next_ordinal;
        visit [->:HasStage:->];
    }

    can inspect_stage with StageNode entry {
        if here.ordinal == self.target_ordinal {
            self.selected = here.name;
            disengage;
        }
    }
}

def _select_next_stage(item: dict[str, any]) -> str {
    graph = CaseGraph(case_id=item["_id"] as str,
        next_ordinal=item["assessment"]["next_stage"] as int);
    nodes: list[StageNode] = [];
    for ordinal in range(len(STAGES)) {
        stage_node = StageNode(name=STAGES[ordinal], ordinal=ordinal);
        nodes.append(stage_node);
        graph +>:HasStage():+> stage_node;
    }
    try {
        selector = graph spawn SelectNextStage();
        return selector.selected;
    } finally {
        for stage_node in nodes { del stage_node; }
        del graph;
    }
}
