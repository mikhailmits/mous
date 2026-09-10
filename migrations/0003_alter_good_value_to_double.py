"""Auto-generated migration.

Created: 2026-09-08 22:29:27
"""

depends_on = "0002_add_good_occurred_on"


def upgrade(ctx):
    """Apply migration."""
    ctx.alter_column("good", "value", column_type={
    'kind': 'double'
})


def downgrade(ctx):
    """Revert migration."""
    pass
