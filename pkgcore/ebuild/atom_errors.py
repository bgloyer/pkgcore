# Copyright: 2005 Brian Harring <ferringb@gmail.com>
# License: GPL2

# "More than one statement on a single line"
# pylint: disable-msg=C0321

"""
atom exceptions
"""

from pkgcore.package import errors

class MalformedAtom(errors.InvalidDependency):

    def __init__(self, atom, err=''):
        errors.InvalidDependency.__init__(
            self, "atom '%s' is malformed: error %s" % (atom, err))
        self.atom, self.err = atom, err


class InvalidVersion(errors.InvalidDependency):

    def __init__(self, ver, rev, err=''):
        errors.InvalidDependency.__init__(
            self,
            "Version restriction ver='%s', rev='%s', is malformed: error %s" %
            (ver, rev, err))
        self.ver, self.rev, self.err = ver, rev, err
