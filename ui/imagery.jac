# Jac 0.34.13 serves the project's assets/ directory; binary JS imports are not supported by its asset copier.
cl def:pub device_photo(model: str) -> str {
    if model in ["Pro 15", "Fixora Demo FD-200"] { return "/assets/imagery/laptop-graphite.jpg"; }
    if model in ["Air 13", "Fixora Demo FD-300"] { return "/assets/imagery/laptop-compact.jpg"; }
    return "/assets/imagery/laptop-silver.jpg";
}
