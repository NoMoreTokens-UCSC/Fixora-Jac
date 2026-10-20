import from "lucide-react" { ArrowRight, Store, Moon, Sun, Eye, EyeOff, Info, LoaderCircle }
import from ..components.ui.button { Button }
import from ..components.ui.input { Input }
import from ..components.ui.field { Field, FieldLabel }
import from .brand { BrandMark }
import from .motion { TitleMotion }
import from .gateway { owner_login, error_message }

def:pub DemoLogin(dark: bool, onTheme: Callable[[], None], onLogin: Callable[[str], None]) -> JsxElement {
    has password: str = "";
    has error: str = "";
    has busy: bool = False;
    has show_password: bool = False;
    async def submit(e: FormEvent) -> None {
        e.preventDefault();
        if busy { return; }
        busy = True; error = "";
        try { await owner_login(password); password = ""; onLogin("owner"); }
        except Exception as e { error = error_message(e); }
        finally { busy = False; }
    }
    return <main className="login-shell">
        <section className="login-entry" aria-labelledby="login-title">
            <header className="login-header"><a className="login-brand" href="#" aria-label="Fixora home"><BrandMark/><span>fixora.</span></a><Button variant="ghost" size="icon" aria-label={"Switch to light mode" if dark else "Switch to dark mode"} onClick={onTheme}>{if dark { <Sun size={18}/> } else { <Moon size={18}/> }}</Button></header>
            <div className="login-form-wrap"><span className="eyebrow">SHOP OWNER WORKSPACE</span><h1 id="login-title"><TitleMotion>Sign in</TitleMotion></h1><p className="login-subtitle">Review WhatsApp cases and make the next step clear.</p>
                <form className="login-form" onSubmit={submit}>
                    <Field><FieldLabel htmlFor="login-password">Owner password</FieldLabel><div className="login-password"><Input id="login-password" type={"text" if show_password else "password"} autoComplete="current-password" placeholder="Enter your owner password" value={password} onChange={lambda (e: ChangeEvent) { password = e.target.value; error = ""; }} aria-invalid={bool(error)} aria-describedby={"login-error" if error else None}/><Button type="button" variant="ghost" size="icon" aria-label={"Hide password" if show_password else "Show password"} onClick={lambda { show_password = not show_password; }}>{if show_password { <EyeOff size={17}/> } else { <Eye size={17}/> }}</Button></div></Field>
                    {if error { <p id="login-error" className="login-error" role="alert"><Info size={14}/>{error}</p> }}
                    <Button type="submit" disabled={busy or not password} className="login-submit">{if busy { <LoaderCircle size={16} className="spin"/> }}Sign in<ArrowRight size={16}/></Button>
                </form><p className="login-demo-note">Customers contact Fixora through WhatsApp. This private workspace is for the shop owner.</p>
            </div><footer className="login-entry-footer"><span>Care, without the confusion.</span><span>FIXORA / WHATSAPP</span></footer>
        </section>
        <section className="login-feature" aria-label="About your Fixora workspace"><div className="login-feature-top"><span>LAPTOP CARE, CONNECTED.</span><Store size={20}/></div><div className="login-feature-content"><div className="login-showcase"><div className="showcase-heading"><span>FIXORA LAPTOP SHOP</span><span className="showcase-indicator"><span/>WhatsApp connected</span></div><div className="showcase-product"><img src="/assets/imagery/laptop-silver.jpg" alt="Illustrative unbranded laptop" width={360} height={270}/><div><strong>A clearer path<br/>from issue to repair.</strong></div></div></div><div className="login-feature-copy"><span className="feature-index">SHOP OWNER</span><h2><TitleMotion>Every detail. One workspace.</TitleMotion></h2><p>Review saved evidence, reply to customers in WhatsApp, and approve repair proposals with the full picture.</p></div></div><div className="login-feature-footer"><BrandMark/><span>Thoughtful support.<br/>From the first message onward.</span></div></section>
    </main>;
}
