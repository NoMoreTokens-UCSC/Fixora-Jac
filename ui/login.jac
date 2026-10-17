import from "lucide-react" { ArrowRight, MessageSquare, Store, Moon, Sun, Eye, EyeOff, Info, Headphones, Check, ArrowUpRight }
import from ..components.ui.button { Button }
import from ..components.ui.input { Input }
import from ..components.ui.field { Field, FieldLabel }
import from .brand { BrandMark }
import from .motion { TitleMotion }
import from .gateway { error_message }

def:pub DemoLogin(dark: bool, onTheme: Callable[[], None], onLogin: Callable[[str, str, str], any]) -> JsxElement {
    has role: str = "customer";
    has email: str = "";
    has password: str = "";
    has error: str = "";
    has show_password: bool = False;
    has help_open: bool = False;
    has connecting: bool = False;
    def choose_role(value: str) { role = value; email = ""; password = ""; error = ""; }
    def fill_demo() { email = "owner@fixora.demo" if role == "owner" else "customer@fixora.demo"; password = "Fixora123!"; error = ""; }
    async def submit(e: FormEvent) -> None {
        e.preventDefault();
        if connecting { return; }
        if not email.strip() or not password { error = "Enter your demo email and password."; return; }
        connecting = True;
        try { await onLogin(role, email, password); }
        except Exception as failure { error = error_message(failure); }
        finally { connecting = False; }
    }
    return <main className="login-shell">
        <section className="login-entry" aria-labelledby="login-title">
            <header className="login-header"><a className="login-brand" href="#" aria-label="Fixora home"><BrandMark/><span>fixora.</span></a><Button variant="ghost" size="icon" aria-label={"Switch to light mode" if dark else "Switch to dark mode"} onClick={onTheme}>{if dark { <Sun size={18}/> } else { <Moon size={18}/> }}</Button></header>
            <div className="login-form-wrap"><h1 id="login-title"><TitleMotion>Sign in</TitleMotion></h1><p className="login-subtitle">Good to see you. Let's take care of the next step.</p>
                <div className="login-role-picker" role="group" aria-label="Demo account type"><Button variant="ghost" aria-pressed={role == "customer"} className={"login-role " + ("selected" if role == "customer" else "")} onClick={lambda { choose_role("customer"); }}><MessageSquare size={16}/>Customer</Button><Button variant="ghost" aria-pressed={role == "owner"} className={"login-role " + ("selected" if role == "owner" else "")} onClick={lambda { choose_role("owner"); }}><Store size={16}/>Shop owner</Button></div>
                <form className="login-form" onSubmit={submit} noValidate={True}>
                    <Field><FieldLabel htmlFor="login-email">Email address</FieldLabel><Input id="login-email" type="email" autoComplete="username" value={email} placeholder={"owner@fixora.demo" if role == "owner" else "customer@fixora.demo"} onChange={lambda (e: ChangeEvent) { email = e.target.value; error = ""; }} aria-invalid={bool(error)} aria-describedby={"login-error" if error else None}/></Field>
                    <Field><FieldLabel htmlFor="login-password">Password</FieldLabel><div className="login-password"><Input id="login-password" type={"text" if show_password else "password"} autoComplete="current-password" placeholder="Enter your password" value={password} onChange={lambda (e: ChangeEvent) { password = e.target.value; error = ""; }} aria-invalid={bool(error)} aria-describedby={"login-error" if error else None}/><Button type="button" variant="ghost" size="icon" aria-label={"Hide password" if show_password else "Show password"} onClick={lambda { show_password = not show_password; }}>{if show_password { <EyeOff size={17}/> } else { <Eye size={17}/> }}</Button></div></Field>
                    {if error { <p id="login-error" className="login-error" role="alert"><Info size={14}/>{error}</p> }}
                    <div className="login-form-meta"><span>MongoDB-connected workspace</span><button type="button" onClick={lambda { help_open = not help_open; }} aria-expanded={help_open}>Need login help?</button></div><Button type="submit" className="login-submit" disabled={connecting}>{"Connecting…" if connecting else "Sign in"}<ArrowRight size={16}/></Button>
                </form>
                <div className="login-divider"><span>TRY THE DEMO</span></div>
                <div className="demo-credentials"><div className="demo-account-heading"><span>{"Shop owner account" if role == "owner" else "Customer account"}</span><span>DEMO</span></div><dl><dt>Email</dt><dd>{"owner@fixora.demo" if role == "owner" else "customer@fixora.demo"}</dd><dt>Password</dt><dd>Fixora123!</dd></dl><Button variant="outline" onClick={fill_demo}>Use demo credentials<ArrowUpRight size={15}/></Button></div>
                {if help_open { <div className="login-help" role="status">Choose an account above, then use the demo credentials to fill the form. Both accounts use Fixora123! No account creation or password recovery is needed in this preview.</div> }}
                <p className="login-demo-note">Shared hackathon accounts select a view. Both roles access the same shop cases. The server stores cases and evidence in MongoDB; these accounts do not enforce customer ownership.</p>
            </div><footer className="login-entry-footer"><span>Care, without the confusion.</span><span>FIXORA / DEMO</span></footer>
        </section>
        <section className="login-feature" aria-label="About your Fixora workspace"><div className="login-feature-top"><span>LAPTOP CARE, CONNECTED.</span><button onClick={lambda { help_open = not help_open; }} aria-expanded={help_open}><Headphones size={16}/>Support</button></div>
            <div className="login-feature-content"><div className="login-showcase"><div className="showcase-heading"><span>FIXORA LAPTOP SHOP</span><span className="showcase-indicator"><span/>Sample case</span></div><div className="showcase-product"><img src="/assets/imagery/laptop-silver.jpg" alt="Illustrative unbranded laptop" width={360} height={270}/><div><span>STUDIO 14</span><strong>A clearer path<br/>from issue to repair.</strong></div></div><div className="showcase-case"><span className="showcase-case-icon"><Check size={17}/></span><div><strong>{"Ready for your review" if role == "owner" else "Your evidence, all together"}</strong><span>FX-1048 · Charging connection</span></div><ArrowUpRight size={18}/></div></div>
                <div className="login-feature-copy"><span className="feature-index">{"02 / SHOP OWNER" if role == "owner" else "01 / CUSTOMER"}</span><h2><TitleMotion key={role}>{"Every detail. One workspace." if role == "owner" else "A conversation that goes further."}</TitleMotion></h2><p>{"Review invoices, photos and saved specialist findings, with the evidence behind each provisional repair proposal." if role == "owner" else "Share what's wrong, upload your photos and invoice, and review the saved assessment at every step."}</p><div className="feature-pagination" aria-hidden="true"><span className={"current" if role == "customer" else ""}/><span className={"current" if role == "owner" else ""}/></div></div>
            </div><div className="login-feature-footer"><BrandMark/><span>Thoughtful support.<br/>From the first message onward.</span></div>
        </section>
    </main>;
}
