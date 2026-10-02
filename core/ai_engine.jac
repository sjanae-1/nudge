"""AI engine -- shared types for LLM-backed task decomposition.

The LLM functions themselves (`breakdown_task`, `review_task_size`) live
in `core/api.jac` next to their only callers: the client bundler
mis-types cross-module `by llm()` calls, while same-module calls compile
cleanly (the proven day-planner pattern). This module owns the
structured output types the model fills in.
"""

"""One micro-step of a broken-down goal, paced with its own deadline."""
obj PlanStep {
    has title: str,
        est_minutes: int,
        due_date: str = "";
}
sem PlanStep.due_date = "Planned day for this step (yyyy-mm-dd), spread between today and the goal's deadline and never after it.";

"""Verdict of the AI size review: is this task too big for one sitting?"""
obj SizeReview {
    has too_large: bool = False,
        reason: str = "",
        steps: list[PlanStep] = [];
}
sem SizeReview.too_large = "True when the goal realistically cannot be finished in one day or a few hours.";
sem SizeReview.reason = "One short sentence saying why the goal is too large; empty when too_large is false.";
sem SizeReview.steps = "When too_large is true, the 3-6 paced micro-steps that split the work up; otherwise empty.";
