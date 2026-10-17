import from "framer-motion" { motion, useReducedMotion }

def:pub TitleMotion(className: str = "", children: any = None) -> JsxElement {
    reduce = useReducedMotion();
    return <motion.span className={"title-motion " + className} initial={False if reduce else {"opacity": 0, "y": 7}} animate={{"opacity": 1, "y": 0}} transition={{"duration": 0 if reduce else 0.38, "ease": "easeOut"}}>{children}</motion.span>;
}
