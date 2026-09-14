"""Deliberately failing fixture used to verify non-success reporting."""
if __name__ == "__main__":
    print("Expected fixture failure: missing demo configuration")
    raise SystemExit(7)
