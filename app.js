class QuantumAITech {
    constructor() {
        this.currentSection = 'dashboard';
        this.expenses = [
            {
                id: 1,
                date: '2025-06-28',
                merchant: 'Office Supplies UK',
                amount: 156.78,
                category: 'Office Supplies',
                description: 'Stationery and printing supplies',
                status: 'Categorized',
                receipt: true
            },
            {
                id: 2,
                date: '2025-06-27',
                merchant: 'Fuel Station',
                amount: 45.20,
                category: 'Transport',
                description: 'Business travel fuel',
                status: 'Categorized',
                receipt: true
            },
            {
                id: 3,
                date: '2025-06-26',
                merchant: 'Software Solutions',
                amount: 299.99,
                category: 'Software',
                description: 'Annual subscription',
                status: 'Pending Review',
                receipt: false
            }
        ];
        this.chatMessages = [];
        this.init();
    }

    init() {
        this.setupNavigation();
        this.marketPricing = new MarketPricing(document.getElementById('market-pricing'));
        // Initialize other features here as needed
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