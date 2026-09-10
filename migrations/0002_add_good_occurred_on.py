"""Auto-generated migration.

Created: 2026-09-07 20:42:51
"""

depends_on = "0001_create_updatesource_table"


def upgrade(ctx):
    """Apply migration."""
    ctx.add_column("good", {
    'name': 'occurred_on',
    'column_type': {
        'kind': 'date'
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
    ctx.create_index("good", {
    'name': 'good_occurred_on_idx',
    'fields': [
        'occurred_on'
    ],
    'unique': False,
    'method': None
})


def downgrade(ctx):
    """Revert migration."""
    ctx.drop_index("good", "good_occurred_on_idx")
    ctx.drop_column("good", "occurred_on")
