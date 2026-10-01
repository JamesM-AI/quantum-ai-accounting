class QuantumAITech {
    constructor() {
        this.currentSection = 'market-pricing';
        this.init();
    }

    init() {
        this.setupNavigation();
        this.marketPricing = new MarketPricing(document.getElementById('market-pricing'));
        this.marketPricing.show();
    }

    setupNavigation() {
        const navButtons = document.querySelectorAll('.nav-btn');
        const sections = document.querySelectorAll('.section');

        navButtons.forEach(button => {
            button.addEventListener('click', () => {
                const target = button.getAttribute('data-section');
                this.switchSection(target);
            });
        });
    }

    switchSection(target) {
        document.querySelectorAll('.section').forEach(section => {
            section.classList.remove('active');
        });
        const targetSection = document.getElementById(target);
        if(targetSection) {
            targetSection.classList.add('active');
        }

        document.querySelectorAll('.nav-btn').forEach(btn => {
            btn.classList.toggle('active', btn.getAttribute('data-section') === target);
        });

        this.currentSection = target;

        if (target === 'market-pricing' && this.marketPricing) {
            this.marketPricing.show();
        }
    }
}


window.addEventListener('DOMContentLoaded', () => {
    const app = new QuantumAITech();
});