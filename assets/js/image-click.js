// Mache alle Bilder in Artikeln anklickbar, um sie im Vollbild zu öffnen
document.addEventListener('DOMContentLoaded', function() {
    // Finde alle Bilder in Artikeln
    const images = document.querySelectorAll('.post-content img, article img');
    
    images.forEach(function(img) {
        // Mache das Bild anklickbar
        img.style.cursor = 'pointer';
        img.title = 'Klicken zum Vergrößern';
        
        img.addEventListener('click', function() {
            // Öffne das Bild im selben Tab
            window.open(this.src, '_self');
        });
    });
});
