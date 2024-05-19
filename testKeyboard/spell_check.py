
# spell_check.py
from hanspell import spell_checker

def correct_text(text):
    spelled_sent = spell_checker.check(text)
    corrected_text = spelled_sent.checked
    
    errors = spelled_sent.errors
    corrections = {}
    if errors:
        for error in errors:
            corrections[error['original']] = error['corrected']
    
    return corrected_text, corrections

if __name__ == "__main__":
    import sys
    import json
    text = sys.argv[1]
    corrected_text, corrections = correct_text(text)
    print(corrected_text)
    print(json.dumps(corrections))
