import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
// Agentforce Conversation Client (ACC) — headless router for the in-LEX chat panel.
// open(botId) pops the panel; execute(utterance, botId) seeds a natural-language turn.
// Desktop Lightning Experience only, API 59.0+. execute() does NOT return the reply.
import { open, execute } from 'lightning/accApi';

// ──────────────────────────────────────────────────────────────────────────
// AGENT CONFIG — paste the real 18-char agent Ids (0Xx...) here.
// `prompt` is optional: leave '' to just open the panel, or set a seed utterance
// that is sent the moment the agent opens.
// ──────────────────────────────────────────────────────────────────────────
const AGENTS = {
    sales: { botId: '0XxdL000003eFOPSA2', prompt: '' },
    booking: { botId: '0XxdL000003eFMnSAM', prompt: 'Hi' },
    onboarding: { botId: '0XxdL000003eFY5SAM', prompt: 'Hi' }
};

export default class RepCockpit extends LightningElement {
    launching = false;

    // ── Greeting ────────────────────────────────────────────────────────────
    get repName() {
        return 'Salesforce Dev';
    }

    get greeting() {
        const hour = new Date().getHours();
        if (hour < 12) return 'Good morning';
        if (hour < 17) return 'Good afternoon';
        return 'Good evening';
    }

    get todayLabel() {
        return new Intl.DateTimeFormat('en-IN', {
            weekday: 'long',
            day: 'numeric',
            month: 'long'
        }).format(new Date());
    }

    // ── Mock KPI tiles (placeholder "live" data for the demo) ────────────────
    get kpis() {
        return [
            {
                key: 'tasks',
                value: '12',
                label: 'Open tasks',
                meta: '3 due today',
                icon: 'utility:task',
                iconClass: 'cockpit-kpi__icon cockpit-kpi__icon_blue'
            },
            {
                key: 'expenses',
                value: '₹14,250',
                label: 'Unlinked expenses',
                meta: '5 receipts this month',
                icon: 'utility:money',
                iconClass: 'cockpit-kpi__icon cockpit-kpi__icon_amber'
            },
            {
                key: 'visits',
                value: '8',
                label: 'Visits this week',
                meta: '2 awaiting follow-up',
                icon: 'utility:checkin',
                iconClass: 'cockpit-kpi__icon cockpit-kpi__icon_green'
            },
            {
                key: 'pipeline',
                value: '₹62.4L',
                label: 'Open pipeline',
                meta: 'across 31 opportunities',
                icon: 'utility:opportunity',
                iconClass: 'cockpit-kpi__icon cockpit-kpi__icon_purple'
            }
        ];
    }

    // ── Agent launcher cards ─────────────────────────────────────────────────
    get actions() {
        return [
            {
                key: 'sales',
                title: 'Opportunities Management',
                desc: 'Review pipeline, surface top deals, and update stages — hands-free.',
                cta: 'Open Sales Agent',
                icon: 'utility:opportunity',
                iconClass: 'cockpit-action__icon cockpit-action__icon_sales'
            },
            {
                key: 'booking',
                title: 'Customer Management',
                desc: 'Pull up customer history and book the next touchpoint in seconds.',
                cta: 'Open Booking Agent',
                icon: 'utility:people',
                iconClass: 'cockpit-action__icon cockpit-action__icon_booking'
            },
            {
                key: 'onboarding',
                title: 'Onboarding',
                desc: 'Guided setup for new reps — accounts, tools, and first-week checklist.',
                cta: 'Open Onboarding Agent',
                icon: 'utility:education',
                iconClass: 'cockpit-action__icon cockpit-action__icon_onboarding'
            }
        ];
    }

    // ── Launch an agent via the ACC router ───────────────────────────────────
    async handleLaunch(event) {
        const key = event.currentTarget.dataset.agent;
        const agent = AGENTS[key];
        if (!agent) {
            this.toast('Error', `No agent configured for "${key}".`, 'error');
            return;
        }
        this.launching = true;
        try {
            await open(agent.botId);
            if (agent.prompt) {
                await execute(agent.prompt, agent.botId);
            }
        } catch (e) {
            this.toast(
                'Could not open assistant',
                e?.message || 'The Agentforce panel is unavailable on this page.',
                'error'
            );
        } finally {
            this.launching = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}