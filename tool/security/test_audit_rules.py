import unittest
from audit_rules import audit

class AuditTests(unittest.TestCase):
    def test_known_secure_exact_match(self):
        rules = 'allow read: if member(group);'
        self.assertTrue(audit(rules, rules)['exact_match'])
    def test_permissive_authenticated_rule_rejected(self):
        self.assertTrue(audit('', 'allow read, write: if request.auth != null;')['broad_authenticated_access_detected'])
    def test_different_rules_not_certified(self):
        self.assertFalse(audit('deny', 'allow')['exact_match'])

if __name__ == '__main__': unittest.main()
