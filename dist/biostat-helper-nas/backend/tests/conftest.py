import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.models.models import Base
from app.models.models import User, UserSetting


@pytest.fixture()
def db_session():
    """Fresh in-memory SQLite session per test, built from the current models."""
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
    )
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    try:
        yield session
    finally:
        session.close()
        engine.dispose()


@pytest.fixture()
def user(db_session):
    user = User(username="tester", email="t@example.com", hashed_password="x")
    db_session.add(user)
    db_session.commit()
    db_session.refresh(user)
    db_session.add(UserSetting(user_id=user.id))
    db_session.commit()
    return user


@pytest.fixture()
def project(db_session, user):
    from app.crud.project import create_project
    from app.schemas.project import ProjectCreate

    return create_project(
        db_session,
        ProjectCreate(name="SAP项目", protocol_no="P-01", status="active", create_standard_workflow=False),
        owner_id=user.id,
    )