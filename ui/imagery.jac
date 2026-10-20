# Jac 0.34.13 serves the project's assets/ directory; binary JS imports are not supported by its asset copier.
cl def:pub device_photo(model: str) -> str {
    if model == "Pro 15" { return "/assets/imagery/laptop-graphite.jpg"; }
    if model == "Air 13" { return "/assets/imagery/laptop-compact.jpg"; }
    return "/assets/imagery/laptop-silver.jpg";
}
