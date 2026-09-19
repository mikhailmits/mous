class LastAccountError(Exception):
    """Raised when deleting the last remaining account."""


class LastDefaultError(Exception):
    """Raised when clearing the last remaining default currency."""
