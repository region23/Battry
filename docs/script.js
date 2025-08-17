// Internationalization data
const translations = {
    en: {
        // Hero section
        'hero.title': 'Advanced Battery Monitoring for macOS',
        'hero.subtitle': 'Professional-grade battery analytics, health scoring, and autonomy testing in your menu bar',
        'hero.download': 'Download for macOS',
        'hero.github': 'View on GitHub',
        'hero.requirements': 'macOS 14.6+ • Apple Silicon & Intel',

        // Features section
        'features.title': 'Key Features',
        'features.realtime.title': 'Real-time Monitoring',
        'features.realtime.desc': 'Live battery metrics in your menu bar with detailed percentage, cycles, temperature, and voltage tracking',
        'features.autonomy.title': 'Autonomy Testing',
        'features.autonomy.desc': 'Complete 100% → 5% discharge tests with automatic start/stop and comprehensive HTML reports',
        'features.health.title': 'Health Scoring',
        'features.health.desc': 'Advanced analytics engine with 0-100 health scoring, wear analysis, and personalized recommendations',
        'features.charts.title': 'Interactive Charts',
        'features.charts.desc': 'Detailed Swift Charts visualization with charge trends, temperature, voltage, and discharge rate analysis',
        'features.loadgen.title': 'Load Generator',
        'features.loadgen.desc': 'Built-in CPU/GPU stress testing with configurable profiles for consistent discharge testing',
        'features.reports.title': 'HTML Reports',
        'features.reports.desc': 'Beautiful, shareable reports with embedded charts, device info, and detailed analysis results',

        // Screenshots section
        'screenshots.title': 'Application Interface',
        'screenshots.overview': 'Overview Panel',
        'screenshots.charts': 'Charts & Analytics',
        'screenshots.test': 'Autonomy Testing',

        // Technical section
        'technical.title': 'Technical Excellence',
        'technical.native.title': 'Native SwiftUI',
        'technical.native.desc': 'Built with SwiftUI and Combine for optimal performance and seamless macOS integration',
        'technical.native.menubar': 'Menu bar integration',
        'technical.native.iokit': 'Direct IOKit access',
        'technical.native.reactive': 'Reactive data flow',
        'technical.data.title': 'Smart Data Management',
        'technical.data.desc': 'Efficient history storage with automatic cleanup and intelligent data aggregation',
        'technical.data.retention': '30-day data retention',
        'technical.data.aggregation': 'Automatic aggregation',
        'technical.data.json': 'JSON persistence',
        'technical.safety.title': 'Safety Systems',
        'technical.safety.desc': 'Built-in safety guards to protect your device during intensive testing',
        'technical.safety.temperature': 'Temperature monitoring',
        'technical.safety.battery': 'Battery level protection',
        'technical.safety.thermal': 'Thermal pressure detection',

        // Download section
        'download.title': 'Get Battry Today',
        'download.desc': 'Free, open-source, and ready to provide deep insights into your Mac\'s battery health',
        'download.requirements.title': 'System Requirements',
        'download.requirements.macos': 'macOS:',
        'download.requirements.processor': 'Processor:',
        'download.requirements.space': 'Storage:',
        'download.button': 'Download Latest Version',

        // Footer
        'footer.github': 'GitHub Repository',
        'footer.releases': 'All Releases',
        'footer.issues': 'Report Issues',
        'footer.contact': 'Contact Developer',
        'footer.made': 'Made with ❤️ by region23',
        'footer.license': 'Licensed under MIT • Open Source'
    },
    ru: {
        // Hero section
        'hero.title': 'Продвинутый мониторинг батареи для macOS',
        'hero.subtitle': 'Профессиональная аналитика батареи, оценка здоровья и тестирование автономности в строке меню',
        'hero.download': 'Скачать для macOS',
        'hero.github': 'Посмотреть на GitHub',
        'hero.requirements': 'macOS 14.6+ • Apple Silicon и Intel',

        // Features section
        'features.title': 'Основные возможности',
        'features.realtime.title': 'Мониторинг в реальном времени',
        'features.realtime.desc': 'Актуальные метрики батареи в строке меню с детальным отслеживанием процентов, циклов, температуры и напряжения',
        'features.autonomy.title': 'Тестирование автономности',
        'features.autonomy.desc': 'Полные тесты разряда 100% → 5% с автоматическим запуском/остановкой и подробными HTML отчетами',
        'features.health.title': 'Оценка здоровья',
        'features.health.desc': 'Продвинутый движок аналитики с оценкой здоровья 0-100, анализом износа и персональными рекомендациями',
        'features.charts.title': 'Интерактивные графики',
        'features.charts.desc': 'Детальная визуализация Swift Charts с трендами заряда, температуры, напряжения и анализом скорости разряда',
        'features.loadgen.title': 'Генератор нагрузки',
        'features.loadgen.desc': 'Встроенное стресс-тестирование CPU/GPU с настраиваемыми профилями для постоянного тестирования разряда',
        'features.reports.title': 'HTML отчеты',
        'features.reports.desc': 'Красивые, разшариваемые отчеты со встроенными графиками, информацией об устройстве и детальными результатами анализа',

        // Screenshots section
        'screenshots.title': 'Интерфейс приложения',
        'screenshots.overview': 'Панель обзора',
        'screenshots.charts': 'Графики и аналитика',
        'screenshots.test': 'Тестирование автономности',

        // Technical section
        'technical.title': 'Техническое совершенство',
        'technical.native.title': 'Нативный SwiftUI',
        'technical.native.desc': 'Создано с SwiftUI и Combine для оптимальной производительности и бесшовной интеграции с macOS',
        'technical.native.menubar': 'Интеграция в строку меню',
        'technical.native.iokit': 'Прямой доступ к IOKit',
        'technical.native.reactive': 'Реактивный поток данных',
        'technical.data.title': 'Умное управление данными',
        'technical.data.desc': 'Эффективное хранение истории с автоматической очисткой и интеллектуальной агрегацией данных',
        'technical.data.retention': '30-дневное хранение данных',
        'technical.data.aggregation': 'Автоматическая агрегация',
        'technical.data.json': 'JSON постоянство',
        'technical.safety.title': 'Системы безопасности',
        'technical.safety.desc': 'Встроенные защитные механизмы для защиты устройства во время интенсивного тестирования',
        'technical.safety.temperature': 'Мониторинг температуры',
        'technical.safety.battery': 'Защита уровня батареи',
        'technical.safety.thermal': 'Обнаружение термального давления',

        // Download section
        'download.title': 'Получите Battry сегодня',
        'download.desc': 'Бесплатно, с открытым исходным кодом и готово предоставить глубокое понимание здоровья батареи вашего Mac',
        'download.requirements.title': 'Системные требования',
        'download.requirements.macos': 'macOS:',
        'download.requirements.processor': 'Процессор:',
        'download.requirements.space': 'Хранилище:',
        'download.button': 'Скачать последнюю версию',

        // Footer
        'footer.github': 'GitHub репозиторий',
        'footer.releases': 'Все релизы',
        'footer.issues': 'Сообщить об ошибке',
        'footer.contact': 'Связаться с разработчиком',
        'footer.made': 'Сделано с ❤️ от region23',
        'footer.license': 'Лицензия MIT • Открытый исходный код'
    }
};

// Current language state
let currentLanguage = 'en';

// DOM Content Loaded
document.addEventListener('DOMContentLoaded', function() {
    initializeLanguage();
    initializeAnimations();
    initializeLanguageToggle();
    initializeSmoothScrolling();
});

// Language Management
function initializeLanguage() {
    // Detect browser language
    const browserLang = navigator.language || navigator.userLanguage;
    const detectedLang = browserLang.startsWith('ru') ? 'ru' : 'en';
    
    // Check localStorage for saved preference
    const savedLang = localStorage.getItem('battry-lang');
    currentLanguage = savedLang || detectedLang;
    
    updateLanguage(currentLanguage);
}

function initializeLanguageToggle() {
    const langButtons = document.querySelectorAll('.lang-btn');
    
    langButtons.forEach(btn => {
        btn.addEventListener('click', function() {
            const lang = this.dataset.lang;
            if (lang !== currentLanguage) {
                switchLanguage(lang);
            }
        });
    });
}

function switchLanguage(lang) {
    currentLanguage = lang;
    localStorage.setItem('battry-lang', lang);
    updateLanguage(lang);
    
    // Update active button
    document.querySelectorAll('.lang-btn').forEach(btn => {
        btn.classList.remove('active');
        if (btn.dataset.lang === lang) {
            btn.classList.add('active');
        }
    });
}

function updateLanguage(lang) {
    const elements = document.querySelectorAll('[data-key]');
    
    elements.forEach(element => {
        const key = element.dataset.key;
        if (translations[lang] && translations[lang][key]) {
            if (element.tagName === 'INPUT' || element.tagName === 'TEXTAREA') {
                element.placeholder = translations[lang][key];
            } else {
                element.textContent = translations[lang][key];
            }
        }
    });
    
    // Update screenshots based on language
    updateScreenshots(lang);
    
    // Update document language
    document.documentElement.lang = lang;
    
    // Update page title
    document.title = lang === 'ru' 
        ? 'Battry - Продвинутый мониторинг батареи для macOS'
        : 'Battry - Advanced macOS Battery Monitor';
}

// Update screenshot sources based on language
function updateScreenshots(lang) {
    const screenshots = document.querySelectorAll('.screenshot-img[data-screenshot]');
    
    screenshots.forEach(img => {
        const screenshotNumber = img.dataset.screenshot;
        const newSrc = `screenshots/${lang}/screenshot${screenshotNumber}.png`;
        
        // Add loading state
        img.style.opacity = '0.5';
        
        // Create new image to preload
        const newImg = new Image();
        newImg.onload = function() {
            img.src = newSrc;
            img.style.opacity = '1';
        };
        newImg.onerror = function() {
            // Fallback to English if language-specific screenshot not found
            if (lang !== 'en') {
                const fallbackSrc = `screenshots/en/screenshot${screenshotNumber}.png`;
                const fallbackImg = new Image();
                fallbackImg.onload = function() {
                    img.src = fallbackSrc;
                    img.style.opacity = '1';
                };
                fallbackImg.onerror = function() {
                    img.style.opacity = '0.3';
                    console.warn('Screenshot not found:', fallbackSrc);
                };
                fallbackImg.src = fallbackSrc;
            } else {
                img.style.opacity = '0.3';
                console.warn('Screenshot not found:', newSrc);
            }
        };
        newImg.src = newSrc;
    });
}

// Animation Management
function initializeAnimations() {
    const observerOptions = {
        threshold: 0.1,
        rootMargin: '0px 0px -50px 0px'
    };

    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('animate');
                observer.unobserve(entry.target);
            }
        });
    }, observerOptions);

    // Observe all elements with animation data attributes
    document.querySelectorAll('[data-animation]').forEach(el => {
        observer.observe(el);
    });
}

// Smooth Scrolling
function initializeSmoothScrolling() {
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function (e) {
            e.preventDefault();
            const target = document.querySelector(this.getAttribute('href'));
            if (target) {
                target.scrollIntoView({
                    behavior: 'smooth',
                    block: 'start'
                });
            }
        });
    });
}

// Lightbox functionality
function openLightbox(img) {
    const lightbox = document.getElementById('lightbox');
    const lightboxImg = document.getElementById('lightbox-img');
    
    lightboxImg.src = img.src;
    lightboxImg.alt = img.alt;
    lightbox.classList.add('active');
    
    // Disable body scroll
    document.body.style.overflow = 'hidden';
}

function closeLightbox() {
    const lightbox = document.getElementById('lightbox');
    lightbox.classList.remove('active');
    
    // Re-enable body scroll
    document.body.style.overflow = '';
}

// Close lightbox on Escape key
document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
        closeLightbox();
    }
});

// Prevent lightbox close when clicking on image
document.querySelector('.lightbox-content').addEventListener('click', function(e) {
    e.stopPropagation();
});

// Parallax effect for hero section
window.addEventListener('scroll', function() {
    const scrolled = window.pageYOffset;
    const hero = document.querySelector('.hero');
    const heroHeight = hero.offsetHeight;
    
    if (scrolled < heroHeight) {
        const rate = scrolled * -0.5;
        hero.style.transform = `translateY(${rate}px)`;
    }
});

// Dynamic navigation highlight (if we had navigation)
window.addEventListener('scroll', function() {
    const sections = document.querySelectorAll('section[id]');
    const scrollPos = window.scrollY + 100;

    sections.forEach(section => {
        const sectionTop = section.offsetTop;
        const sectionHeight = section.offsetHeight;
        const sectionId = section.getAttribute('id');
        
        if (scrollPos >= sectionTop && scrollPos < sectionTop + sectionHeight) {
            // Could highlight navigation items here if we had them
        }
    });
});

// Add loading states for images
document.addEventListener('DOMContentLoaded', function() {
    const images = document.querySelectorAll('img');
    
    images.forEach(img => {
        // Add loading placeholder
        img.style.opacity = '0';
        img.style.transition = 'opacity 0.3s ease';
        
        img.addEventListener('load', function() {
            this.style.opacity = '1';
        });
        
        // Handle error case
        img.addEventListener('error', function() {
            this.style.opacity = '0.5';
            console.warn('Failed to load image:', this.src);
        });
    });
});

// Feature card hover effects
document.addEventListener('DOMContentLoaded', function() {
    const featureCards = document.querySelectorAll('.feature-card');
    
    featureCards.forEach(card => {
        card.addEventListener('mouseenter', function() {
            this.style.transform = 'translateY(-10px) scale(1.02)';
        });
        
        card.addEventListener('mouseleave', function() {
            this.style.transform = 'translateY(0) scale(1)';
        });
    });
});

// Add download tracking (optional analytics)
function trackDownload() {
    // Could add analytics tracking here
    console.log('Download tracked');
}

// Add all download buttons click tracking
document.addEventListener('DOMContentLoaded', function() {
    const downloadButtons = document.querySelectorAll('a[href*="releases"]');
    
    downloadButtons.forEach(button => {
        button.addEventListener('click', trackDownload);
    });
});

// Easter egg - Konami code
let konamiCode = false;
let konamiSequence = [];
const konamiTarget = [38, 38, 40, 40, 37, 39, 37, 39, 66, 65]; // ↑↑↓↓←→←→BA

document.addEventListener('keydown', function(e) {
    konamiSequence.push(e.keyCode);
    
    if (konamiSequence.length > konamiTarget.length) {
        konamiSequence.shift();
    }
    
    if (konamiSequence.length === konamiTarget.length) {
        if (konamiSequence.every((key, index) => key === konamiTarget[index])) {
            if (!konamiCode) {
                konamiCode = true;
                // Add some fun effect
                document.body.style.filter = 'hue-rotate(180deg)';
                setTimeout(() => {
                    document.body.style.filter = '';
                    konamiCode = false;
                }, 2000);
            }
        }
    }
});

// Performance optimization - lazy load images
function initializeLazyLoading() {
    const images = document.querySelectorAll('img[data-src]');
    
    const imageObserver = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                const img = entry.target;
                img.src = img.dataset.src;
                img.removeAttribute('data-src');
                imageObserver.unobserve(img);
            }
        });
    });

    images.forEach(img => imageObserver.observe(img));
}

// Initialize lazy loading if needed
document.addEventListener('DOMContentLoaded', initializeLazyLoading);