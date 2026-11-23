from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest
from fastapi import HTTPException
from sqlalchemy.exc import OperationalError

from app.crud.study import transaction


def postgres_session():
    db = MagicMock()
    db.bind.dialect.name = 'postgresql'
    return db


def test_postgres_mutation_uses_transaction_local_lock_timeout():
    db = postgres_session()
    with transaction(db, 1):
        pass
    assert str(db.execute.call_args.args[0]) == "SET LOCAL lock_timeout = '5s'"
    db.commit.assert_called_once()
    db.rollback.assert_not_called()


@pytest.mark.parametrize('attribute', ['sqlstate', 'pgcode'])
def test_lock_timeout_is_retryable_and_rolls_back_without_exposing_sql(attribute):
    db = postgres_session()
    error = OperationalError('sensitive SQL', {}, SimpleNamespace(**{attribute: '55P03'}))
    db.query.side_effect = error
    with pytest.raises(HTTPException) as caught:
        with transaction(db, 1):
            pytest.fail('must not enter the mutation')
    assert caught.value.status_code == 503
    assert caught.value.headers['Retry-After'] == '2'
    assert '保存锁' in caught.value.detail
    assert 'sensitive' not in caught.value.detail
    db.rollback.assert_called_once()
    db.commit.assert_not_called()


def test_other_database_failures_are_not_mislabelled_as_lock_timeout():
    db = postgres_session()
    error = OperationalError('SQL', {}, SimpleNamespace(pgcode='08006'))
    db.query.side_effect = error
    with pytest.raises(OperationalError):
        with transaction(db, 1):
            pass
    db.rollback.assert_called_once()
