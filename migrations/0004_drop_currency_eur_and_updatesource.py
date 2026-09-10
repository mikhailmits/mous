"""Auto-generated migration.

Created: 2026-09-10 17:34:52
"""

depends_on = "0003_alter_good_value_to_double"


def _is_default_column():
    return {
        'name': 'is_default',
        'column_type': {
            'kind': 'boolean'
        },
        'db_type': None,
        'nullable': False,
        'primary_key': False,
        'unique': False,
        'default': '0',
        'auto_increment': False,
        'max_length': None,
        'max_digits': None,
        'decimal_places': None
    }


def _category_id_column():
    return {
        'name': 'category_id',
        'column_type': {
            'kind': 'big_integer'
        },
        'db_type': None,
        'nullable': True,
        'primary_key': False,
        'unique': False,
        'default': None,
        'auto_increment': False,
        'max_length': None,
        'max_digits': None,
        'decimal_places': None
    }


def _rebuild_sqlite(ctx):
    """SQLite cannot DROP FK/CHECK or ADD FK; rebuild the affected tables."""
    ctx.execute("PRAGMA foreign_keys=OFF")
    ctx.execute(
        """
        CREATE TABLE currency__new (
            id INTEGER PRIMARY KEY,
            symbol VARCHAR(8) NOT NULL UNIQUE,
            name VARCHAR(64) NOT NULL UNIQUE,
            is_default BOOLEAN NOT NULL DEFAULT 0
        )
        """
    )
    ctx.execute(
        "INSERT INTO currency__new (id, symbol, name, is_default) "
        "SELECT id, symbol, name, is_default FROM currency"
    )
    ctx.execute("DROP TABLE currency")
    ctx.execute("ALTER TABLE currency__new RENAME TO currency")
    ctx.execute("DROP TABLE updatesource")
    ctx.execute("DROP INDEX IF EXISTS good_occurred_on_idx")
    ctx.execute(
        """
        CREATE TABLE good__new (
            id INTEGER PRIMARY KEY,
            name VARCHAR(128) NOT NULL,
            value REAL NOT NULL,
            occurred_on TEXT NOT NULL,
            currency_id INTEGER NOT NULL,
            account_id INTEGER NOT NULL,
            category_id INTEGER,
            FOREIGN KEY (currency_id) REFERENCES currency (id) ON DELETE RESTRICT ON UPDATE CASCADE,
            FOREIGN KEY (account_id) REFERENCES account (id) ON DELETE CASCADE ON UPDATE CASCADE,
            FOREIGN KEY (category_id) REFERENCES goodcategory (id) ON DELETE SET NULL ON UPDATE CASCADE
        )
        """
    )
    ctx.execute(
        "INSERT INTO good__new (id, name, value, occurred_on, currency_id, account_id) "
        "SELECT id, name, value, occurred_on, currency_id, account_id FROM good"
    )
    ctx.execute("DROP TABLE good")
    ctx.execute("ALTER TABLE good__new RENAME TO good")
    ctx.execute("CREATE INDEX good_occurred_on_idx ON good (occurred_on)")
    ctx.execute("PRAGMA foreign_keys=ON")


def upgrade(ctx):
    """Apply migration."""
    ctx.create_table(
        "goodcategory",
        fields=[
            {
                'name': 'id',
                'column_type': {
                    'kind': 'big_integer'
                },
                'db_type': None,
                'nullable': True,
                'primary_key': True,
                'unique': False,
                'default': None,
                'auto_increment': False,
                'max_length': None,
                'max_digits': None,
                'decimal_places': None
            },
            {
                'name': 'name',
                'column_type': {
                    'kind': 'string',
                    'length': 30
                },
                'db_type': None,
                'nullable': False,
                'primary_key': False,
                'unique': True,
                'default': None,
                'auto_increment': False,
                'max_length': 30,
                'max_digits': None,
                'decimal_places': None
            }
        ],
    )
    ctx.add_column("currency", _is_default_column())
    ctx.execute(
        "UPDATE currency SET is_default = 1 WHERE id = (SELECT id FROM currency ORDER BY id LIMIT 1)"
    )
    sqlite_execute = ctx.dialect == "sqlite" and getattr(ctx, "_mode", "execute") == "execute"
    if sqlite_execute:
        _rebuild_sqlite(ctx)
        return
    ctx.drop_foreign_key("currency", "fk_currency_update_source_id")
    ctx.drop_check("currency", "positive_rate")
    ctx.drop_table("updatesource")
    ctx.drop_column("currency", "this_in_eur")
    ctx.drop_column("currency", "update_source_id")
    ctx.add_column("good", _category_id_column())
    ctx.add_foreign_key(
        "good",
        "fk_good_category_id",
        ['category_id'],
        "goodcategory",
        ['id'],
        on_delete="SET NULL",
        on_update="CASCADE",
    )


def downgrade(ctx):
    """Revert migration."""
    ctx.drop_foreign_key("good", "fk_good_category_id")
    ctx.drop_column("good", "category_id")
    ctx.add_column("currency", {
    'name': 'update_source_id',
    'column_type': {
        'kind': 'big_integer'
    },
    'db_type': None,
    'nullable': True,
    'primary_key': False,
    'unique': False,
    'default': None,
    'auto_increment': False,
    'max_length': None,
    'max_digits': None,
    'decimal_places': None
})
    ctx.add_column("currency", {
    'name': 'this_in_eur',
    'column_type': {
        'kind': 'double'
    },
    'db_type': None,
    'nullable': False,
    'primary_key': False,
    'unique': False,
    'default': None,
    'auto_increment': False,
    'max_length': None,
    'max_digits': None,
    'decimal_places': None
})
    ctx.drop_column("currency", "is_default")
    ctx.create_table(
        "updatesource",
        fields=[
                       {
                           'name': 'id',
                           'column_type': {
                               'kind': 'big_integer'
                           },
                           'db_type': None,
                           'nullable': True,
                           'primary_key': True,
                           'unique': False,
                           'default': None,
                           'auto_increment': False,
                           'max_length': None,
                           'max_digits': None,
                           'decimal_places': None
                       },
                       {
                           'name': 'url',
                           'column_type': {
                               'kind': 'string',
                               'length': 2048
                           },
                           'db_type': None,
                           'nullable': False,
                           'primary_key': False,
                           'unique': True,
                           'default': None,
                           'auto_increment': False,
                           'max_length': 2048,
                           'max_digits': None,
                           'decimal_places': None
                       },
                       {
                           'name': 'title',
                           'column_type': {
                               'kind': 'string',
                               'length': 128
                           },
                           'db_type': None,
                           'nullable': False,
                           'primary_key': False,
                           'unique': False,
                           'default': None,
                           'auto_increment': False,
                           'max_length': 128,
                           'max_digits': None,
                           'decimal_places': None
                       }
                   ],
    )
    ctx.add_check("currency", "positive_rate", "this_in_eur > 0")
    ctx.add_foreign_key(
        "currency",
        "fk_currency_update_source_id",
        ['update_source_id'],
        "updatesource",
        ['id'],
        on_delete="SET NULL",
        on_update="CASCADE",
    )
    ctx.drop_table("goodcategory")
