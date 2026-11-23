from sqlalchemy import inspect, text

from app.db.database import engine


def _normalize_project_phase(value):
    return "流程待办" if not value or value == "额外待办" else value


def run_lightweight_migrations() -> None:
    """Apply small additive migrations for deployments without Alembic."""
    inspector = inspect(engine)

    # create_all runs before this function and creates these additive tables on
    # existing deployments. The explicit indexes keep project workspace reads
    # responsive for large timeline histories.
    with engine.begin() as connection:
        table_names = set(inspector.get_table_names())
        if "project_members" in table_names:
            connection.execute(text(
                "CREATE INDEX IF NOT EXISTS ix_project_members_project_id "
                "ON project_members (project_id)"
            ))
        if "project_timeline_imports" in table_names:
            connection.execute(text(
                "CREATE INDEX IF NOT EXISTS ix_project_timeline_imports_project_id "
                "ON project_timeline_imports (project_id)"
            ))
        if "project_timeline_items" in table_names:
            connection.execute(text(
                "CREATE INDEX IF NOT EXISTS ix_project_timeline_items_project_id "
                "ON project_timeline_items (project_id)"
            ))

    if "users" in inspector.get_table_names():
        user_columns = {column["name"] for column in inspector.get_columns("users")}
        if "is_admin" not in user_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE users ADD COLUMN is_admin BOOLEAN DEFAULT false"))

    if "user_settings" in inspector.get_table_names():
        setting_columns = {column["name"] for column in inspector.get_columns("user_settings")}
        additive_columns = {
            "theme_seed": "VARCHAR(30) DEFAULT 'biostat'",
            "use_dynamic_color": "BOOLEAN DEFAULT false",
            "amoled_dark": "BOOLEAN DEFAULT false",
            "weekly_review_at": "TIMESTAMP",
        }
        with engine.begin() as connection:
            for column_name, column_type in additive_columns.items():
                if column_name not in setting_columns:
                    connection.execute(text(f"ALTER TABLE user_settings ADD COLUMN {column_name} {column_type}"))

    if "nas_videos" in inspector.get_table_names():
        nas_video_columns = {column["name"] for column in inspector.get_columns("nas_videos")}
        additive_columns = {
            "category_id": "INTEGER",
            "episode_number": "INTEGER",
            "sort_order": "INTEGER DEFAULT 0",
            "is_manual": "BOOLEAN DEFAULT false",
            "thumbnail_url": "VARCHAR(500)",
        }
        with engine.begin() as connection:
            for column_name, column_type in additive_columns.items():
                if column_name not in nas_video_columns:
                    connection.execute(text(f"ALTER TABLE nas_videos ADD COLUMN {column_name} {column_type}"))

    if "notes" in inspector.get_table_names():
        note_columns = {column["name"] for column in inspector.get_columns("notes")}
        if "task_id" not in note_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE notes ADD COLUMN task_id INTEGER"))

    if "project_todos" in inspector.get_table_names():
        todo_columns = {column["name"] for column in inspector.get_columns("project_todos")}
        if "start_at" not in todo_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE project_todos ADD COLUMN start_at TIMESTAMP"))
        additive_columns = {
            "contexts": "TEXT",
            "tags": "TEXT",
            "area": "VARCHAR(50)",
            "energy_level": "VARCHAR(20)",
            "time_estimate": "INTEGER",
            "is_focused_today": "BOOLEAN DEFAULT false",
            "review_at": "TIMESTAMP",
            "completed_at": "TIMESTAMP",
            "cancelled_at": "TIMESTAMP",
            "recurrence": "VARCHAR(40)",
        }
        with engine.begin() as connection:
            for column_name, column_type in additive_columns.items():
                if column_name not in todo_columns:
                    connection.execute(text(f"ALTER TABLE project_todos ADD COLUMN {column_name} {column_type}"))

    if "project_todo_checklist_items" in inspector.get_table_names():
        checklist_columns = {
            column["name"]
            for column in inspector.get_columns("project_todo_checklist_items")
        }
        if "due_at" not in checklist_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE project_todo_checklist_items ADD COLUMN due_at TIMESTAMP"))
        if "meeting_id" not in checklist_columns:
            with engine.begin() as connection:
                connection.execute(text("ALTER TABLE project_todo_checklist_items ADD COLUMN meeting_id INTEGER"))

    if "projects" in inspector.get_table_names() and "project_phases" in inspector.get_table_names():
        project_columns = {column["name"] for column in inspector.get_columns("projects")}
        additive_columns = {
            "current_workflow_phase": "VARCHAR(100)",
            "project_type": "VARCHAR(50) DEFAULT 'other' NOT NULL",
            "is_cdisc": "BOOLEAN DEFAULT false NOT NULL",
            "is_inbox": "BOOLEAN DEFAULT false",
            "review_at": "TIMESTAMP",
            "is_focused": "BOOLEAN DEFAULT false",
        }
        with engine.begin() as connection:
            for column_name, column_type in additive_columns.items():
                if column_name not in project_columns:
                    connection.execute(
                        text(f"ALTER TABLE projects ADD COLUMN {column_name} {column_type}")
                    )

            projects = connection.execute(text("SELECT id FROM projects")).fetchall()
            for (project_id,) in projects:
                # SAP and TFL specifications are one coordinated stage. Merge
                # the two legacy buckets while preserving every existing todo.
                phase_rows = connection.execute(
                    text(
                        "SELECT id, name, sort_order FROM project_phases "
                        "WHERE project_id = :project_id ORDER BY sort_order, id"
                    ),
                    {"project_id": project_id},
                ).fetchall()
                candidates = [
                    row for row in phase_rows
                    if row[1] in {"SAP与TFL", "方案与SAP", "TFL与统计输出"}
                ]
                if candidates:
                    keeper = next(
                        (row for row in candidates if row[1] == "SAP与TFL"),
                        candidates[0],
                    )
                    connection.execute(
                        text(
                            "UPDATE project_phases SET name = 'SAP与TFL', "
                            "sort_order = :sort_order WHERE id = :phase_id"
                        ),
                        {
                            "phase_id": keeper[0],
                            "sort_order": min(row[2] or 100000 for row in candidates),
                        },
                    )
                    for duplicate in candidates:
                        if duplicate[0] != keeper[0]:
                            connection.execute(
                                text("DELETE FROM project_phases WHERE id = :phase_id"),
                                {"phase_id": duplicate[0]},
                            )

                if "project_todos" in inspector.get_table_names():
                    connection.execute(
                        text(
                            "UPDATE project_todos SET phase = 'SAP与TFL' "
                            "WHERE project_id = :project_id "
                            "AND phase IN ('方案与SAP', 'TFL与统计输出')"
                        ),
                        {"project_id": project_id},
                    )

                existing = connection.execute(
                    text("SELECT name FROM project_phases WHERE project_id = :project_id"),
                    {"project_id": project_id},
                ).fetchall()
                existing_names = {row[0] for row in existing}
                next_order = len(existing_names) + 1

                if "project_todos" in inspector.get_table_names():
                    todo_phases = connection.execute(
                        text("SELECT DISTINCT phase FROM project_todos WHERE project_id = :project_id"),
                        {"project_id": project_id},
                    ).fetchall()
                    for (phase_value,) in todo_phases:
                        phase_name = _normalize_project_phase(phase_value)
                        if phase_name in existing_names:
                            continue
                        connection.execute(
                            text(
                                "INSERT INTO project_phases "
                                "(project_id, name, sort_order, created_at, updated_at) "
                                "VALUES (:project_id, :name, :sort_order, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
                            ),
                            {
                                "project_id": project_id,
                                "name": phase_name,
                                "sort_order": next_order,
                            },
                        )
                        existing_names.add(phase_name)
                        next_order += 1

            connection.execute(
                text(
                    "UPDATE projects SET current_workflow_phase = 'SAP与TFL' "
                    "WHERE current_workflow_phase IN ('方案与SAP', 'TFL与统计输出')"
                )
            )
            if "project_todos" in inspector.get_table_names():
                connection.execute(
                    text(
                        "UPDATE projects SET is_cdisc = true WHERE id IN ("
                        "SELECT DISTINCT project_id FROM project_todos "
                        "WHERE title LIKE '%SDTM%' OR title LIKE '%ADaM%' "
                        "OR title LIKE '%define.xml%' OR phase = 'CDISC与数据集'"
                        ")"
                    )
                )
