// Exact manual distances from Cabintan for staff display (source of truth)
window.MANUAL_DISTANCES = {
  "Airport": 25.7,
  "Alegria": 25.2,
  "Alta Vista": 26.3,
  "Bagongbong": 31.6,
  "Bagong Buhay": 24,
  "Bantigue": 28.3,
  "Barangay South (Poblacion) (1-8, 12-13, 15, 17, 23, 27)": 26,
  "Barangay East (Poblacion) (9-11, 16, 18, 25, 28)": 26,
  "Barangay West (Poblacion) (14, 19, 20-22, 24, 26)": 26,
  "Barangay North (Poblacion) (29)": 25.7,
  "Batuan": 26,
  "Bayog": 34,
  "Biliboy": 23.4,
  "Borok": 33.2,
  "Cabaon‑an": 17.9,
  "Cabintan": 0,
  "Cabulihan": 26.8,
  "Cagbuhangin": 26.9,
  "Camp Downes": 26.6,
  "Can‑adieng": 26.3,
  "Can‑untog": 33.7,
  "Catmon": 26.9,
  "Cogon Combado": 24,
  "Concepcion": 25.3,
  "Curva": 32.9,
  "Lake Danao": 11.3,
  "Danhug": 32.1,
  "Dayhagan": 22.6,
  "Dolores": 16.4,
  "Domonar": 34.2,
  "Don Felipe Larrazabal": 26.6,
  "Don Potenciano Larrazabal": 42.6,
  "Doña Feliza Z. Mejia": 26.9,
  "Donghol": 24.9,
  "Esperansa": 41.1,
  "Gaas": 20.2,
  "Green Valley": 37.3,
  "Guintigui‑an": 33.7,
  "Hibunawon": 29.7,
  "Hugpa": 34.7,
  "Ipil": 31.2,
  "Juaton": 23.5,
  "Kadaohan": 27.9,
  "Labrador (Balion)": 34.6,
  "Lao": 30,
  "Leondoni": 35.8,
  "Libertad": 27.3,
  "Liberty": 22.1,
  "Licuma": 33.1,
  "Liloan": 30.9,
  "Linao": 25.9,
  "Luna": 18.3,
  "Mabato": 32,
  "Mabini": 36,
  "Macabug": 33,
  "Magaswi": 23.6,
  "Mahayag": 32.9,
  "Mahayahay": 39,
  "Manlilinao": 45.5,
  "Margen": 36,
  "Mas‑in": 37.3,
  "Matica‑a": 31.5,
  "Milagro": 19.4,
  "Monterico": 45.4,
  "Nasunogan": 25.9,
  "Naungan": 27.1,
  "Nueva Sociedad": 38.9,
  "Nueva Vista": 19.5,
  "Patag": 30.8,
  "Punta": 24.7,
  "Quezon, Jr.": 38.6,
  "Rufina M. Tan (Rawis)": 37.7,
  "Sabang Bao": 35.5,
  "Salvacion": 23.4,
  "San Antonio": 31.8,
  "San Isidro": 25.9,
  "San Jose": 30.7,
  "San Juan": 34,
  "San Pablo (Simangan)": 20.8,
  "San Vicente": 34.6,
  "Santo Niño": 23.3,
  "Sumangga": 31,
  "Tambulilid": 26.3,
  "Tongonan": 25.1,
  "Valencia": 29.1
};

// Restore AccurateBarangayUtils to use manual distances for staff display
(function(){
  function buildRecord(name) {
    const distance = window.MANUAL_DISTANCES[name];
    const isReference = name === 'Cabintan';
    return {
      name,
      distance,
      coordinates: null,
      classification: null,
      coastal: false,
      suggestedFee: 0,
      isReference,
      calculatedAt: null
    };
  }
  const ManualUtils = {
    getAllBarangays() { return Object.keys(window.MANUAL_DISTANCES); },
    getBarangayData(name) { return Object.prototype.hasOwnProperty.call(window.MANUAL_DISTANCES, name) ? buildRecord(name) : null; },
    getReferencePoint() { return buildRecord('Cabintan'); },
    getStatistics() {
      const values = Object.values(window.MANUAL_DISTANCES).map(Number).filter(v => !isNaN(v));
      const total = values.length;
      const min = total ? Math.min.apply(null, values) : 0;
      const max = total ? Math.max.apply(null, values) : 0;
      const avg = total ? values.reduce((a,b)=>a+b,0)/total : 0;
      return { total, minDistance: min, maxDistance: max, averageDistance: avg, urban: 0, rural: 0 };
    }
  };
  window.AccurateBarangayUtils = ManualUtils;
})();


