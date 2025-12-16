// Simular los datos que deberían verse
const route1 = {
  name: "Madrid → Barcelona",
  totalSamples: 25,
  jkStandard: 1,
  // Si On-Time es 100%, significa que todos los 25 samples están en ≤1 día
  distribution: new Map([
    [0, 11],  // 11 samples en 0 días (44%)
    [1, 14],  // 14 samples en 1 día (56%)
    // Total: 25 samples, todos ≤1 día = 100% on-time
  ])
};

const route2 = {
  name: "Barcelona → Madrid",
  totalSamples: 25,
  jkStandard: 1,
  // Si On-Time es 96%, significa que 24 de 25 están en ≤1 día
  distribution: new Map([
    [0, 6],   // 6 samples en 0 días (24%)
    [1, 18],  // 18 samples en 1 día (72%)
    [2, 1],   // 1 sample en 2 días (4%) - este es el que falla
    // Total: 25 samples, 24 ≤1 día = 96% on-time
  ])
};

function calculateCumulative(route) {
  console.log(`\n${route.name}:`);
  console.log(`Total samples: ${route.totalSamples}`);
  console.log(`J+K Standard: ${route.jkStandard}d`);
  
  let cumulative = 0;
  const days = Array.from(route.distribution.keys()).sort((a, b) => a - b);
  
  days.forEach(day => {
    const count = route.distribution.get(day);
    cumulative += count;
    const percentage = (cumulative / route.totalSamples) * 100;
    const color = day <= route.jkStandard ? 'GREEN' : 'RED';
    console.log(`  ${day}d: ${count} samples, cumulative: ${cumulative}/${route.totalSamples} = ${percentage.toFixed(1)}% [${color}]`);
  });
}

calculateCumulative(route1);
calculateCumulative(route2);
