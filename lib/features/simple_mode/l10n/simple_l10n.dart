import 'package:flutter/widgets.dart';

/// Localized strings helper for Simple Mode across all 6 supported languages:
/// English (en), Spanish (es), French (fr), German (de), Italian (it), Dutch (nl).
class SimpleL10n {
  SimpleL10n._();

  static const _supportedLanguages = ['en', 'es', 'fr', 'de', 'it', 'nl'];

  static String _lang(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    return _supportedLanguages.contains(code) ? code : 'en';
  }

  static String navBuy(BuildContext context) => switch (_lang(context)) {
        'es' => 'Comprar',
        'fr' => 'Acheter',
        'de' => 'Kaufen',
        'it' => 'Compra',
        'nl' => 'Kopen',
        _ => 'Buy',
      };

  static String navSell(BuildContext context) => switch (_lang(context)) {
        'es' => 'Vender',
        'fr' => 'Vendre',
        'de' => 'Verkaufen',
        'it' => 'Vendi',
        'nl' => 'Verkopen',
        _ => 'Sell',
      };

  static String navTrades(BuildContext context) => switch (_lang(context)) {
        'es' => 'Mis operaciones',
        'fr' => 'Mes opérations',
        'de' => 'Meine Trades',
        'it' => 'Operazioni',
        'nl' => 'Mijn trades',
        _ => 'My Trades',
      };

  static String navProfile(BuildContext context) => switch (_lang(context)) {
        'es' => 'Perfil',
        'fr' => 'Profil',
        'de' => 'Profil',
        'it' => 'Profilo',
        'nl' => 'Profiel',
        _ => 'Profile',
      };

  static String navHelp(BuildContext context) => switch (_lang(context)) {
        'es' => 'Ayuda',
        'fr' => 'Aide',
        'de' => 'Hilfe',
        'it' => 'Aiuto',
        'nl' => 'Hulp',
        _ => 'Help',
      };

  static String communityVerified(BuildContext context) => switch (_lang(context)) {
        'es' => 'Comunidad verificada',
        'fr' => 'Communauté vérifiée',
        'de' => 'Verifizierte Gemeinschaft',
        'it' => 'Comunità verificata',
        'nl' => 'Geverifieerde community',
        _ => 'Verified community',
      };

  static String generalMarket(BuildContext context) => switch (_lang(context)) {
        'es' => 'Mercado General',
        'fr' => 'Marché Général',
        'de' => 'Allgemeiner Markt',
        'it' => 'Mercato Generale',
        'nl' => 'Algemene Markt',
        _ => 'General Market',
      };

  static String scanCommunityQr(BuildContext context) => switch (_lang(context)) {
        'es' => 'Escanear QR de comunidad',
        'fr' => 'Scanner le QR de communauté',
        'de' => 'Community-QR scannen',
        'it' => 'Scansiona QR comunità',
        'nl' => 'Scan community QR',
        _ => 'Scan community QR',
      };

  static String enterMarket(BuildContext context) => switch (_lang(context)) {
        'es' => 'Entrar al mercado',
        'fr' => 'Entrer sur le marché',
        'de' => 'Markt betreten',
        'it' => 'Entra nel mercato',
        'nl' => 'Betreed de markt',
        _ => 'Enter market',
      };

  static String simpleMode(BuildContext context) => switch (_lang(context)) {
        'es' => 'Modo Simple',
        'fr' => 'Mode Simple',
        'de' => 'Einfacher Modus',
        'it' => 'Modalità Semplice',
        'nl' => 'Eenvoudige Modus',
        _ => 'Simple Mode',
      };

  static String advancedMode(BuildContext context) => switch (_lang(context)) {
        'es' => 'Modo Avanzado (Técnico)',
        'fr' => 'Mode Avancé (Technique)',
        'de' => 'Erweiterter Modus (Technisch)',
        'it' => 'Modalità Avanzata (Tecnica)',
        'nl' => 'Geavanceerde Modus (Technisch)',
        _ => 'Advanced Mode (Technical)',
      };

  static String switchToAdvanced(BuildContext context) => switch (_lang(context)) {
        'es' => 'Activar Modo Avanzado',
        'fr' => 'Activer le Mode Avancé',
        'de' => 'Erweiterten Modus aktivieren',
        'it' => 'Attiva Modalità Avanzata',
        'nl' => 'Geavanceerde Modus activeren',
        _ => 'Switch to Advanced Mode',
      };

  static String switchToSimple(BuildContext context) => switch (_lang(context)) {
        'es' => 'Volver a Modo Simple',
        'fr' => 'Retour au Mode Simple',
        'de' => 'Zurück zum einfachen Modus',
        'it' => 'Torna a Modalità Semplice',
        'nl' => 'Terug naar Eenvoudige Modus',
        _ => 'Switch to Simple Mode',
      };

  static String advancedModeDesc(BuildContext context) => switch (_lang(context)) {
        'es' =>
          'Para usuarios técnicos: control de relays Nostr, claves privadas, selector de nodos y diagnósticos.',
        'fr' =>
          'Pour les utilisateurs techniques : gestion des relais Nostr, clés privées, sélecteur de nœuds et diagnostics.',
        'de' =>
          'Für technische Benutzer: Nostr-Relays, private Schlüssel, Node-Auswahl und Diagnose.',
        'it' =>
          'Per utenti tecnici: gestione dei relay Nostr, chiavi private, selezione nodi e diagnostica.',
        'nl' =>
          'Voor technische gebruikers: Nostr-relays, privésleutels, node-selectie en diagnostiek.',
        _ =>
          'For technical users: Nostr relays, private keys, node switcher, and diagnostics.',
      };

  static String howMuchBuy(BuildContext context) => switch (_lang(context)) {
        'es' => '¿Cuánto quieres comprar?',
        'fr' => 'Combien voulez-vous acheter ?',
        'de' => 'Wie viel möchten Sie kaufen?',
        'it' => 'Quanto vuoi comprare?',
        'nl' => 'Hoeveel wil je kopen?',
        _ => 'How much do you want to buy?',
      };

  static String selectPaymentMethod(BuildContext context) => switch (_lang(context)) {
        'es' => 'Selecciona método de pago',
        'fr' => 'Sélectionnez le moyen de paiement',
        'de' => 'Zahlungsmethode auswählen',
        'it' => 'Seleziona metodo di pagamento',
        'nl' => 'Selecteer betaalmethode',
        _ => 'Select payment method',
      };

  static String viewOffers(BuildContext context) => switch (_lang(context)) {
        'es' => 'Ver ofertas',
        'fr' => 'Voir les offres',
        'de' => 'Angebote ansehen',
        'it' => 'Vedi offerte',
        'nl' => 'Bekijk aanbiedingen',
        _ => 'View offers',
      };

  static String buyButton(BuildContext context) => switch (_lang(context)) {
        'es' => 'COMPRAR',
        'fr' => 'ACHETER',
        'de' => 'KAUFEN',
        'it' => 'COMPRA',
        'nl' => 'KOPEN',
        _ => 'BUY',
      };

  static String temporaryGuarantee(BuildContext context) => switch (_lang(context)) {
        'es' => 'Garantía temporal',
        'fr' => 'Garantie temporaire',
        'de' => 'Vorübergehende Garantie',
        'it' => 'Garanzia temporanea',
        'nl' => 'Tijdelijke garantie',
        _ => 'Temporary security guarantee',
      };

  static String temporaryGuaranteeTooltip(BuildContext context) => switch (_lang(context)) {
        'es' =>
          'Se devuelve automáticamente cuando la operación termina correctamente.',
        'fr' =>
          'Remboursé automatiquement lorsque l\'opération se termine avec succès.',
        'de' =>
          'Wird automatisch erstattet, wenn der Trade erfolgreich abgeschlossen ist.',
        'it' =>
          'Restituito automaticamente quando l\'operazione si conclude con successo.',
        'nl' =>
          'Wordt automatisch terugbetaald zodra de transactie succesvol is voltooid.',
        _ =>
          'Automatically refunded when the trade completes successfully.',
      };

  static String receiveEst(BuildContext context) => switch (_lang(context)) {
        'es' => 'Recibes',
        'fr' => 'Vous recevez',
        'de' => 'Sie erhalten',
        'it' => 'Ricevi',
        'nl' => 'Je ontvangt',
        _ => 'You receive',
      };

  static String fee(BuildContext context) => switch (_lang(context)) {
        'es' => 'Comisión',
        'fr' => 'Commission',
        'de' => 'Gebühr',
        'it' => 'Commissione',
        'nl' => 'Commissie',
        _ => 'Fee',
      };

  static String howMuchSell(BuildContext context) => switch (_lang(context)) {
        'es' => '¿Cuánto quieres vender?',
        'fr' => 'Combien voulez-vous vendre ?',
        'de' => 'Wie viel möchten Sie verkaufen?',
        'it' => 'Quanto vuoi vendere?',
        'nl' => 'Hoeveel wil je verkopen?',
        _ => 'How much do you want to sell?',
      };

  static String selectReceiveMethod(BuildContext context) => switch (_lang(context)) {
        'es' => 'Selecciona cómo quieres recibir el dinero',
        'fr' => 'Comment souhaitez-vous recevoir le paiement ?',
        'de' => 'Wie möchten Sie die Zahlung erhalten?',
        'it' => 'Seleziona come ricevere il denaro',
        'nl' => 'Hoe wil je de betaling ontvangen?',
        _ => 'How do you want to receive payment?',
      };

  static String publishOffer(BuildContext context) => switch (_lang(context)) {
        'es' => 'Publicar oferta',
        'fr' => 'Publier l\'offre',
        'de' => 'Angebot veröffentlichen',
        'it' => 'Pubblica offerta',
        'nl' => 'Aanbod publiceren',
        _ => 'Publish offer',
      };

  static String sellStepsTitle(BuildContext context) => switch (_lang(context)) {
        'es' => 'Cómo funciona la venta',
        'fr' => 'Comment fonctionne la vente',
        'de' => 'So funktioniert der Verkauf',
        'it' => 'Come funziona la vendita',
        'nl' => 'Hoe verkopen werkt',
        _ => 'How selling works',
      };

  static String activeTrades(BuildContext context) => switch (_lang(context)) {
        'es' => 'En curso',
        'fr' => 'En cours',
        'de' => 'Aktiv',
        'it' => 'In corso',
        'nl' => 'Actief',
        _ => 'Active',
      };

  static String completedTrades(BuildContext context) => switch (_lang(context)) {
        'es' => 'Cerradas',
        'fr' => 'Terminées',
        'de' => 'Abgeschlossen',
        'it' => 'Completate',
        'nl' => 'Completed',
        _ => 'Completed',
      };

  static String noTrades(BuildContext context) => switch (_lang(context)) {
        'es' => 'Sin operaciones todavía',
        'fr' => 'Pas encore d\'opérations',
        'de' => 'Noch keine Trades',
        'it' => 'Nessuna operazione',
        'nl' => 'Nog geen trades',
        _ => 'No trades yet',
      };

  static String noTradesDesc(BuildContext context) => switch (_lang(context)) {
        'es' => 'Tus compras y ventas aparecerán aquí con su estado en tiempo real.',
        'fr' => 'Vos achats et ventes apparaîtront ici avec leur statut en temps réel.',
        'de' => 'Ihre Käufe und Verkäufe werden hier mit Echtzeitstatus angezeigt.',
        'it' => 'I tuoi acquisti e vendite appariranno qui con stato in tempo reale.',
        'nl' => 'Je aankopen en verkopen verschijnen hier met realtime status.',
        _ => 'Your purchases and sales will appear here with real-time status.',
      };

  static String user(BuildContext context) => switch (_lang(context)) {
        'es' => 'Usuario',
        'fr' => 'Utilisateur',
        'de' => 'Benutzer',
        'it' => 'Utente',
        'nl' => 'Gebruiker',
        _ => 'User',
      };

  static String reputation(BuildContext context) => switch (_lang(context)) {
        'es' => 'Reputación',
        'fr' => 'Réputation',
        'de' => 'Reputation',
        'it' => 'Reputazione',
        'nl' => 'Reputatie',
        _ => 'Reputation',
      };

  static String tradesCompleted(BuildContext context) => switch (_lang(context)) {
        'es' => 'operaciones completadas',
        'fr' => 'opérations terminées',
        'de' => 'abgeschlossene Trades',
        'it' => 'operazioni completate',
        'nl' => 'voltooide transacties',
        _ => 'completed trades',
      };

  static String connectedWallet(BuildContext context) => switch (_lang(context)) {
        'es' => 'Wallet Lightning',
        'fr' => 'Portefeuille Lightning',
        'de' => 'Lightning-Wallet',
        'it' => 'Wallet Lightning',
        'nl' => 'Lightning-wallet',
        _ => 'Lightning Wallet',
      };

  static String walletConnected(BuildContext context) => switch (_lang(context)) {
        'es' => 'Conectada (NWC)',
        'fr' => 'Connecté (NWC)',
        'de' => 'Verbunden (NWC)',
        'it' => 'Collegato (NWC)',
        'nl' => 'Verbonden (NWC)',
        _ => 'Connected (NWC)',
      };

  static String walletDisconnected(BuildContext context) => switch (_lang(context)) {
        'es' => 'No conectada (facturas manuales)',
        'fr' => 'Non connecté (factures manuelles)',
        'de' => 'Nicht verbunden (manuelle Rechnungen)',
        'it' => 'Non collegato (fatture manuali)',
        'nl' => 'Niet verbonden (handmatige facturen)',
        _ => 'Not connected (manual invoices)',
      };

  static String recoveryWords(BuildContext context) => switch (_lang(context)) {
        'es' => 'Palabras de recuperación',
        'fr' => 'Mots de récupération',
        'de' => 'Wiederherstellungswörter',
        'it' => 'Parole di recupero',
        'nl' => 'Herstelwoorden',
        _ => 'Recovery words',
      };

  static String recoveryWordsDesc(BuildContext context) => switch (_lang(context)) {
        'es' =>
          'Guarda tus 12 palabras. Las necesitarás si pierdes o cambias de teléfono.',
        'fr' =>
          'Conservez vos 12 mots. Vous en aurez besoin si vous perdez votre téléphone.',
        'de' =>
          'Bewahren Sie Ihre 12 Wörter auf. Sie benötigen sie bei Verlust des Telefons.',
        'it' =>
          'Salva le tue 12 parole. Ti serviranno se perdi o cambi telefono.',
        'nl' =>
          'Bewaar je 12 woorden. Je hebt ze nodig als je van telefoon wisselt of hem verliest.',
        _ =>
          'Keep your 12 recovery words safe. You need them if you lose your phone.',
      };

  static String helpTitle(BuildContext context) => switch (_lang(context)) {
        'es' => 'Ayuda y Mediación',
        'fr' => 'Aide et Médiation',
        'de' => 'Hilfe & Mediation',
        'it' => 'Aiuto e Mediazione',
        'nl' => 'Hulp & Bemiddeling',
        _ => 'Help & Mediation',
      };

  static String haveProblem(BuildContext context) => switch (_lang(context)) {
        'es' => '¿Hay algún problema?',
        'fr' => 'Un problème ?',
        'de' => 'Gibt es ein Problem?',
        'it' => 'C\'è qualche problema?',
        'nl' => 'Is er een probleem?',
        _ => 'Is there a problem?',
      };

  static String requestHelp(BuildContext context) => switch (_lang(context)) {
        'es' => 'PEDIR AYUDA',
        'fr' => 'DEMANDER DE L\'AIDE',
        'de' => 'HILFE ANFORDERN',
        'it' => 'CHIEDI AIUTO',
        'nl' => 'HULP VRAGEN',
        _ => 'REQUEST HELP',
      };

  static String mediatorInfo(BuildContext context) => switch (_lang(context)) {
        'es' =>
          'Un mediador humano de tu comunidad revisa la operación para resolver cualquier inconveniente.',
        'fr' =>
          'Un médiateur humain de votre communauté examine l\'opération pour résoudre tout problème.',
        'de' =>
          'Ein menschlicher Mediator Ihrer Community prüft die Transaktion, um Probleme zu lösen.',
        'it' =>
          'Un mediatore umano della tua comunità esamina l\'operazione per risolvere qualsiasi problema.',
        'nl' =>
          'Een menselijke bemiddelaar uit je community bekijkt de transactie om problemen op te lossen.',
        _ =>
          'A human community mediator will review the trade to resolve any issue.',
      };

  static String faq(BuildContext context) => switch (_lang(context)) {
        'es' => 'Preguntas frecuentes',
        'fr' => 'Questions fréquentes',
        'de' => 'Häufig gestellte Fragen',
        'it' => 'Domande frequenti',
        'nl' => 'Veelgestelde vragen',
        _ => 'Frequently Asked Questions',
      };

  static String faq1Q(BuildContext context) => switch (_lang(context)) {
        'es' => '¿Qué es la garantía temporal?',
        'fr' => 'Qu\'est-ce que la garantie temporaire ?',
        'de' => 'Was ist die vorübergehende Garantie?',
        'it' => 'Cos\'è la garanzia temporanea?',
        'nl' => 'Wat is de tijdelijke garantie?',
        _ => 'What is the temporary guarantee?',
      };

  static String faq1A(BuildContext context) => switch (_lang(context)) {
        'es' =>
          'Es un depósito de seguridad temporal que protege a ambas partes contra incumplimientos. Se devuelve en su totalidad cuando el trade finaliza correctamente.',
        'fr' =>
          'C\'est un dépôt de sécurité temporaire protégeant les deux parties. Il est intégralement restitué lorsque la transaction se termine avec succès.',
        'de' =>
          'Es ist eine vorübergehende Sicherheitsleistung, die beide Parteien schützt. Sie wird nach erfolgreichem Abschluss vollständig erstattet.',
        'it' =>
          'È un deposito di sicurezza temporaneo che protegge entrambe le parti. Viene restituito integralmente al completamento con successo.',
        'nl' =>
          'Het is een tijdelijke borg die beide partijen beschermt. Het wordt volledig terugbetaald wanneer de transactie succesvol is afgerond.',
        _ =>
          'It is a temporary security deposit that protects both parties against non-performance. It is fully refunded when the trade completes successfully.',
      };

  static String faq2Q(BuildContext context) => switch (_lang(context)) {
        'es' => '¿Está seguro mi Bitcoin durante la operación?',
        'fr' => 'Mon Bitcoin est-il en sécurité pendant l\'opération ?',
        'de' => 'Sind meine Bitcoins während des Trades sicher?',
        'it' => 'Il mio Bitcoin è al sicuro durante l\'operazione?',
        'nl' => 'Is mijn Bitcoin veilig tijdens de transactie?',
        _ => 'Is my Bitcoin safe during the trade?',
      };

  static String faq2A(BuildContext context) => switch (_lang(context)) {
        'es' =>
          'Sí. El Bitcoin queda protegido bajo un contrato de custodia temporal seguro hasta que el vendedor confirme haber recibido el dinero en su cuenta bancaria.',
        'fr' =>
          'Oui. Le Bitcoin est protégé par un contrat de séquestre sécurisé jusqu\'à ce que le vendeur confirme avoir reçu les fonds sur son compte bancaire.',
        'de' =>
          'Ja. Das Bitcoin wird in einer sicheren Treuhand verwahrt, bis der Verkäufer den Geldeingang auf seinem Bankkonto bestätigt.',
        'it' =>
          'Sì. Il Bitcoin rimane protetto in un contratto di custodia sicuro finché il venditore non conferma di aver ricevuto il denaro sul proprio conto bancario.',
        'nl' =>
          'Ja. De Bitcoin wordt veilig bewaard in een tijdelijke escrow totdat de verkoper bevestigt dat het geld op de bankrekening staat.',
        _ =>
          'Yes. The Bitcoin is secured under a temporary escrow contract until the seller verifies receiving the fiat funds in their bank account.',
      };

  static String buyConfirmationTitle(BuildContext context) => switch (_lang(context)) {
        'es' => 'Confirma tu compra',
        'fr' => 'Confirmez votre achat',
        'de' => 'Kauf bestätigen',
        'it' => 'Conferma acquisto',
        'nl' => 'Bevestig aankoop',
        _ => 'Confirm your purchase',
      };

  static String buySummary(BuildContext context) => switch (_lang(context)) {
        'es' => 'Vas a pagar',
        'fr' => 'Vous allez payer',
        'de' => 'Sie zahlen',
        'it' => 'Pagherai',
        'nl' => 'Je betaalt',
        _ => 'You will pay',
      };

  static String youWillReceive(BuildContext context) => switch (_lang(context)) {
        'es' => 'Recibirás',
        'fr' => 'Vous recevrez',
        'de' => 'Sie erhalten',
        'it' => 'Riceverai',
        'nl' => 'Je ontvangt',
        _ => 'You will receive',
      };

  static String refundNotice(BuildContext context) => switch (_lang(context)) {
        'es' => 'Reembolsable al terminar con éxito',
        'fr' => 'Remboursable en fin d\'opération',
        'de' => 'Erstattungsfähig bei Erfolg',
        'it' => 'Rimborsabile al completamento',
        'nl' => 'Terugbetaalbaar na succes',
        _ => 'Refunded upon completion',
      };

  static String paymentDetailsPrompt(BuildContext context) => switch (_lang(context)) {
        'es' => 'Tus datos para recibir el pago',
        'fr' => 'Vos coordonnées pour recevoir le paiement',
        'de' => 'Ihre Angaben für den Zahlungsempfang',
        'it' => 'I tuoi dettagli per ricevere il pagamento',
        'nl' => 'Je gegevens om betaling te ontvangen',
        _ => 'Your details to receive payment',
      };

  static String paymentDetailsHint(BuildContext context) => switch (_lang(context)) {
        'es' => 'Número de cuenta, titular, teléfono móvil o alias...',
        'fr' => 'Numéro de compte, titulaire ou identifiant...',
        'de' => 'Kontonummer, Inhaber oder Mobilnummer...',
        'it' => 'Numero di conto, intestatario o cellulare...',
        'nl' => 'Rekeningnummer, naam of mobiel...',
        _ => 'Account number, holder name or mobile...',
      };

  static String safetyNoticeBuy(BuildContext context) => switch (_lang(context)) {
        'es' =>
          'Verifica cuidadosamente los datos antes de enviar el dinero. Tu Bitcoin estará protegido en custodia.',
        'fr' =>
          'Vérifiez attentivement les données avant d\'envoyer l\'argent. Vos Bitcoins seront protégés.',
        'de' =>
          'Überprüfen Sie die Angaben vor dem Senden sorgfältig. Ihr Bitcoin ist geschützt.',
        'it' =>
          'Verifica attentamente i dati prima di inviare il denaro. I tuoi Bitcoin saranno protetti.',
        'nl' =>
          'Controleer de gegevens zorgvuldig voordat je betaalt. Je Bitcoin is beschermd.',
        _ =>
          'Verify payment details carefully before sending money. Your Bitcoin is protected in escrow.',
      };

  static String safetyNoticeSell(BuildContext context) => switch (_lang(context)) {
        'es' =>
          'Confirma únicamente después de ver el dinero reflejado en tu propia cuenta bancaria. Esta acción no se puede deshacer.',
        'fr' =>
          'Ne confirmez qu\'après avoir vu l\'argent sur votre compte bancaire. Cette action est irréversible.',
        'de' =>
          'Bestätigen Sie erst, wenn das Geld auf Ihrem Bankkonto eingegangen ist. Dies kann nicht rückgängig gemacht werden.',
        'it' =>
          'Conferma solo dopo aver visto i fondi sul tuo conto bancario. Questa azione non può essere annullata.',
        'nl' =>
          'Bevestig pas zodra je het geld op je eigen rekening ziet. Dit kan niet ongedaan worden gemaakt.',
        _ =>
          'Only confirm after seeing the funds in your own bank account. This action cannot be undone.',
      };

  static String confirmAndBuy(BuildContext context) => switch (_lang(context)) {
        'es' => 'CONFIRMAR Y COMPRAR',
        'fr' => 'CONFIRMER ET ACHETER',
        'de' => 'BESTÄTIGEN & KAUFEN',
        'it' => 'CONFERMA E COMPRA',
        'nl' => 'BEVESTIG EN KOOP',
        _ => 'CONFIRM & BUY',
      };

  static String confirmAndPublish(BuildContext context) => switch (_lang(context)) {
        'es' => 'CONFIRMAR Y PUBLICAR',
        'fr' => 'CONFIRMER ET PUBLIER',
        'de' => 'BESTÄTIGEN & VERÖFFENTLICHEN',
        'it' => 'CONFERMA E PUBBLICA',
        'nl' => 'BEVESTIG EN PUBLICEER',
        _ => 'CONFIRM & PUBLISH',
      };

  static String calculatingRate(BuildContext context) => switch (_lang(context)) {
        'es' => 'Calculando sats...',
        'fr' => 'Calcul des sats...',
        'de' => 'Sats werden berechnet...',
        'it' => 'Calcolo sats...',
        'nl' => 'Sats berekenen...',
        _ => 'Calculating sats...',
      };

  static String tradeAccepted(BuildContext context) => switch (_lang(context)) {
        'es' => 'Oferta aceptada',
        'fr' => 'Offre acceptée',
        'de' => 'Angebot angenommen',
        'it' => 'Offerta accettata',
        'nl' => 'Bod geaccepteerd',
        _ => 'Offer accepted',
      };

  static String guaranteeLocked(BuildContext context) => switch (_lang(context)) {
        'es' => 'Garantía temporal bloqueada',
        'fr' => 'Garantie temporaire verrouillée',
        'de' => 'Vorübergehende Garantie gesperrt',
        'it' => 'Garanzia temporanea bloccata',
        'nl' => 'Tijdelijke borg vergrendeld',
        _ => 'Temporary guarantee secured',
      };

  static String bitcoinSecured(BuildContext context) => switch (_lang(context)) {
        'es' => 'Bitcoin protegido en custodia',
        'fr' => 'Bitcoin protégé sous séquestre',
        'de' => 'Bitcoin treuhänderisch geschützt',
        'it' => 'Bitcoin protetto in custodia',
        'nl' => 'Bitcoin beveiligd in escrow',
        _ => 'Bitcoin protected in escrow',
      };

  static String sendFiatStep(BuildContext context) => switch (_lang(context)) {
        'es' => 'Envía el dinero fiat',
        'fr' => 'Envoyez le paiement fiat',
        'de' => 'Fiat-Zahlung senden',
        'it' => 'Invia pagamento fiat',
        'nl' => 'Stuur fiat betaling',
        _ => 'Send fiat payment',
      };

  static String waitingFiatConfirmation(BuildContext context) => switch (_lang(context)) {
        'es' => 'Esperando confirmación del vendedor',
        'fr' => 'En attente de confirmation du vendeur',
        'de' => 'Warten auf Bestätigung des Verkäufers',
        'it' => 'In attesa di conferma del venditore',
        'nl' => 'Wachten op bevestiging van verkoper',
        _ => 'Waiting for seller confirmation',
      };

  static String bitcoinReceived(BuildContext context) => switch (_lang(context)) {
        'es' => 'Bitcoin recibido en tu billetera',
        'fr' => 'Bitcoin reçu dans votre portefeuille',
        'de' => 'Bitcoin in Ihrer Wallet empfangen',
        'it' => 'Bitcoin ricevuto nel tuo wallet',
        'nl' => 'Bitcoin ontvangen in je wallet',
        _ => 'Bitcoin received in your wallet',
      };

  static String tradeCompleted(BuildContext context) => switch (_lang(context)) {
        'es' => '¡Operación completada con éxito!',
        'fr' => 'Opération terminée avec succès !',
        'de' => 'Trade erfolgreich abgeschlossen!',
        'it' => 'Operazione completata con successo!',
        'nl' => 'Transactie succesvol voltooid!',
        _ => 'Trade completed successfully!',
      };

  static String iHavePaid(BuildContext context) => switch (_lang(context)) {
        'es' => 'YA PAGUÉ',
        'fr' => 'J\'AI PAYÉ',
        'de' => 'ICH HABE BEZAHLT',
        'it' => 'HO PAGATO',
        'nl' => 'IK HEB BETAALD',
        _ => 'I HAVE PAID',
      };

  static String iReceivedMoney(BuildContext context) => switch (_lang(context)) {
        'es' => 'RECIBÍ EL DINERO',
        'fr' => 'J\'AI REÇU L\'ARGENT',
        'de' => 'GELD EMPFANGEN',
        'it' => 'HO RICEVUTO IL DENARO',
        'nl' => 'IK HEB HET GELD ONTVANGEN',
        _ => 'I RECEIVED THE MONEY',
      };

  static String confirmPaymentSent(BuildContext context) => switch (_lang(context)) {
        'es' => '¿Confirmas que ya enviaste el dinero a tu contraparte?',
        'fr' => 'Confirmez-vous avoir envoyé l\'argent à votre contrepartie ?',
        'de' => 'Bestätigen Sie, dass Sie das Geld an die Gegenpartei gesendet haben?',
        'it' => 'Confermi di aver inviato il denaro alla controparte?',
        'nl' => 'Bevestig je dat je het geld naar je tegenpartij hebt gestuurd?',
        _ => 'Do you confirm you have sent the fiat funds to your counterparty?',
      };

  static String chatWithCounterpart(BuildContext context) => switch (_lang(context)) {
        'es' => 'Chat con tu contraparte',
        'fr' => 'Chat avec la contrepartie',
        'de' => 'Chat mit der Gegenpartei',
        'it' => 'Chat con la controparte',
        'nl' => 'Chat met tegenpartij',
        _ => 'Chat with counterparty',
      };

  static String mediationCaseReceived(BuildContext context) => switch (_lang(context)) {
        'es' => 'Caso recibido',
        'fr' => 'Dossier reçu',
        'de' => 'Fall erhalten',
        'it' => 'Caso ricevuto',
        'nl' => 'Zaak ontvangen',
        _ => 'Case received',
      };

  static String mediatorAssigned(BuildContext context) => switch (_lang(context)) {
        'es' => 'Mediador de la comunidad asignado',
        'fr' => 'Médiateur de la communauté assigné',
        'de' => 'Community-Mediator zugewiesen',
        'it' => 'Mediatore della comunità assegnato',
        'nl' => 'Communitybemiddelaar toegewezen',
        _ => 'Community mediator assigned',
      };

  static String waitingMediationResolution(BuildContext context) => switch (_lang(context)) {
        'es' => 'Esperando resolución del mediador',
        'fr' => 'En attente de résolution par le médiateur',
        'de' => 'Warten auf Entscheidung des Mediators',
        'it' => 'In attesa di risoluzione del mediatore',
        'nl' => 'Wachten op oplossing van bemiddelaar',
        _ => 'Awaiting mediator resolution',
      };

  static String explainProblem(BuildContext context) => switch (_lang(context)) {
        'es' => 'Explícanos brevemente qué ocurrió:',
        'fr' => 'Expliquez brièvement ce qui s\'est passé :',
        'de' => 'Erklären Sie kurz, was passiert ist:',
        'it' => 'Spiega brevemente cosa è successo:',
        'nl' => 'Leg kort uit wat er is gebeurd:',
        _ => 'Briefly explain what happened:',
      };

  static String sendRequest(BuildContext context) => switch (_lang(context)) {
        'es' => 'Solicitar Asistencia',
        'fr' => 'Demander de l\'aide',
        'de' => 'Hilfe anfordern',
        'it' => 'Richiedi Assistenza',
        'nl' => 'Vraag hulp aan',
        _ => 'Request Assistance',
      };
}
