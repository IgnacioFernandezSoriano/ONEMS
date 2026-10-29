import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { useAccount } from '@/contexts/AccountContext';
import { startOfDayInTz, endOfDayInTz } from '@/lib/dateUtils';
import { useEffectiveAccountId } from '../useEffectiveAccountId';
import type { TimeUnit } from '@/lib/accountTime';
import { buildStandardsIndex, measureHours, measureUnit, routeKey, uniqueStandards } from '@/lib/transitMeasure';

interface CarrierProductData {
  carrier: string;
  product: string;
  routes: number;
  totalSamples: number;
  /** Unidad de jkStandard/jkActual/deviation: 'days' solo si todas las rutas con estandar miden en dias; si no, 'hours' */
  unit: TimeUnit;
  jkStandard: number;
  jkActual: number;
  deviation: number;
  onTimePercentage: number;
  problematicRoutes: number;
  status: 'compliant' | 'warning' | 'critical';
}

interface Filters {
  dateFrom?: string;
  dateTo?: string;
  routeType?: string;
  originCity?: string;
  destinationCity?: string;
  carrier?: string;
  product?: string;
}

export function useCarrierProductOverview(accountId: string | undefined, filters: Filters) {
  const effectiveAccountId = useEffectiveAccountId();
  const { accountTimezone } = useAccount();
  const activeAccountId = effectiveAccountId || accountId;

  const [data, setData] = useState<CarrierProductData[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);
  const [globalWarningThreshold, setGlobalWarningThreshold] = useState<number>(80);
  const [globalCriticalThreshold, setGlobalCriticalThreshold] = useState<number>(75);

  useEffect(() => {
    if (!activeAccountId) {
      setLoading(false);
      return;
    }

    async function fetchData() {
      try {
        setLoading(true);

        // First, get delivery standards with related data
        const { data: standards, error: stdError } = await supabase
          .from('delivery_standards')
          .select(`
            *,
            origin_city:cities!delivery_standards_origin_city_id_fkey(id, name),
            destination_city:cities!delivery_standards_destination_city_id_fkey(id, name),
            carrier:carriers(id, name),
            product:products(id, code, description)
          `)
          .eq('account_id', activeAccountId);

        if (stdError) throw stdError;

        // Indice de estandares por ruta (carrier|product|origin|destination por nombre;
        // producto por description, que es lo que guarda one_db.product_name, y por "code - description")
        const standardsMap = buildStandardsIndex(
          standards || [],
          std => ({
            carrier: std.carrier?.name,
            productCode: std.product?.code,
            productDescription: std.product?.description,
            origin: std.origin_city?.name,
            destination: std.destination_city?.name,
          }),
          std => {
            // Estandar en su propia unidad (sin convertir); la unidad decide la medida
            const unit: TimeUnit = measureUnit(std);
            const jkStandard = std.standard_time;
            const successPct = std.success_percentage || 95;
            const warningThreshold = std.threshold_type === 'relative'
              ? successPct - (successPct * (std.warning_threshold || 5) / 100)
              : successPct - (std.warning_threshold || 5);
            const criticalThreshold = std.threshold_type === 'relative'
              ? successPct - (successPct * (std.critical_threshold || 10) / 100)
              : successPct - (std.critical_threshold || 10);
            return {
              jkStandard: (jkStandard || 0) as number,
              unit,
              successPercentage: successPct as number,
              warningThreshold: warningThreshold as number,
              criticalThreshold: criticalThreshold as number,
            };
          },
        );

        console.log('[useCarrierProductOverview] Loaded standards:', uniqueStandards(standardsMap).length);

        // Calculate global thresholds (average of all standards)
        let warningThreshold = 80;
        let criticalThreshold = 75;
        if (standardsMap.size > 0) {
          const thresholds = uniqueStandards(standardsMap);
          warningThreshold = thresholds.reduce((sum, s) => sum + s.warningThreshold, 0) / thresholds.length;
          criticalThreshold = thresholds.reduce((sum, s) => sum + s.criticalThreshold, 0) / thresholds.length;
        }
        setGlobalWarningThreshold(warningThreshold);
        setGlobalCriticalThreshold(criticalThreshold);
        console.log('[useCarrierProductOverview] Global thresholds:', { warning: warningThreshold, critical: criticalThreshold });

        // Build query for shipments with pagination
        const allShipments: any[] = []
        const pageSize = 1000
        let start = 0
        let hasMore = true

        while (hasMore) {
          let query = supabase
            .from('one_db')
            .select(`
              carrier_name, 
              product_name, 
              on_time_delivery, 
              business_transit_days,
              business_transit_hours,
              origin_city_name,
              destination_city_name
            `)
            .eq('account_id', activeAccountId)
            .range(start, start + pageSize - 1)

          // Use same date filtering as ONE DB (no time adjustment)
          if (filters.dateFrom && filters.dateFrom !== '') {
            query = query.gte('sent_at', startOfDayInTz(filters.dateFrom.slice(0, 10), accountTimezone))
          }
          if (filters.dateTo && filters.dateTo !== '') {
            query = query.lte('sent_at', endOfDayInTz(filters.dateTo.slice(0, 10), accountTimezone))
          }
          if (filters.originCity) {
            query = query.eq('origin_city_name', filters.originCity)
          }
          if (filters.destinationCity) {
            query = query.eq('destination_city_name', filters.destinationCity)
          }
          if (filters.carrier) {
            query = query.eq('carrier_name', filters.carrier)
          }
          if (filters.product) {
            query = query.eq('product_name', filters.product)
          }

          const { data, error: err } = await query

          if (err) throw err

          if (data && data.length > 0) {
            allShipments.push(...data)
            hasMore = data.length === pageSize
            start += pageSize
          } else {
            hasMore = false
          }
        }

        const shipments = allShipments

        // Group by carrier-product combination
        const grouped = new Map<string, {
          routes: Set<string>;
          onTimeCount: number;
          onTimeEvaluated: number; // envios con on_time_delivery no nulo (los nulos no cuentan como tarde)
          total: number;
          hourDistribution: Map<number, number>; // horas (medida de la ruta en horas) -> count
          timedTotal: number;
          daysRoutes: number; // envios cuya ruta tiene estandar en dias
          hoursRoutes: number; // envios cuya ruta tiene estandar en horas
          totalStandardHours: number;
          standardPercentageSum: number;
          standardPercentageCount: number;
          routePerformance: Map<string, { onTime: number; total: number }>;
        }>();

        (shipments || []).forEach(shipment => {
          const key = `${shipment.carrier_name}|${shipment.product_name}`;
          const pairKey = `${shipment.origin_city_name}-${shipment.destination_city_name}`;
          const standardKey = routeKey(shipment.carrier_name, shipment.product_name, shipment.origin_city_name, shipment.destination_city_name);
          const standard = standardsMap.get(standardKey);
          
          if (!grouped.has(key)) {
            grouped.set(key, {
              routes: new Set(),
              onTimeCount: 0,
              onTimeEvaluated: 0,
              total: 0,
              hourDistribution: new Map(),
              timedTotal: 0,
              daysRoutes: 0,
              hoursRoutes: 0,
              totalStandardHours: 0,
              standardPercentageSum: 0,
              standardPercentageCount: 0,
              routePerformance: new Map()
            });
          }
          
          const stats = grouped.get(key)!;
          stats.routes.add(pairKey);
          const hasOnTime = typeof shipment.on_time_delivery === 'boolean';
          if (hasOnTime) {
            stats.onTimeEvaluated += 1;
            stats.onTimeCount += shipment.on_time_delivery ? 1 : 0;
          }
          stats.total += 1;
          
          // Medida segun la unidad del estandar de la ruta, expresada en horas
          const unit: TimeUnit = standard?.unit || 'hours';
          if (standard) {
            if (unit === 'days') stats.daysRoutes++; else stats.hoursRoutes++;
          }
          const transitHours = measureHours(shipment, unit);
          if (transitHours !== null) {
            const bucket = Math.round(transitHours);
            stats.hourDistribution.set(bucket, (stats.hourDistribution.get(bucket) || 0) + 1);
            stats.timedTotal += 1;
          }

          stats.totalStandardHours += (standard?.jkStandard || 0) * (unit === 'days' ? 24 : 1);
          if (standard?.successPercentage) {
            stats.standardPercentageSum += standard.successPercentage;
            stats.standardPercentageCount++;
          }
          
          // Track route performance
          if (!stats.routePerformance.has(pairKey)) {
            stats.routePerformance.set(pairKey, { onTime: 0, total: 0 });
          }
          const routeStats = stats.routePerformance.get(pairKey)!;
          if (hasOnTime) {
            routeStats.onTime += shipment.on_time_delivery ? 1 : 0;
            routeStats.total += 1;
          }
        });

        // Calculate metrics for each carrier-product combination
        const result: CarrierProductData[] = [];
        grouped.forEach((stats, key) => {
          const [carrier, product] = key.split('|');
          const onTimePercentage = stats.onTimeEvaluated > 0 ? (stats.onTimeCount / stats.onTimeEvaluated) * 100 : 0;
          let jkStandard = stats.totalStandardHours / stats.total;
          
          // Calculate J+K Actual (days to reach STD %)
          const targetStdPercentage = stats.standardPercentageCount > 0 
            ? stats.standardPercentageSum / stats.standardPercentageCount 
            : 85;
          
          let jkActual = 0;
          const sortedHours = Array.from(stats.hourDistribution.keys()).sort((a, b) => a - b);
          let cumulativeSamples = 0;
          const targetSamples = (targetStdPercentage / 100) * stats.timedTotal;

          for (const h of sortedHours) {
            cumulativeSamples += stats.hourDistribution.get(h) || 0;
            if (cumulativeSamples >= targetSamples) {
              jkActual = h;
              break;
            }
          }

          // Si todas las rutas con estandar miden en dias, se devuelve en dias; si hay mezcla, en horas
          const groupUnit: TimeUnit = stats.daysRoutes > 0 && stats.hoursRoutes === 0 ? 'days' : 'hours';
          if (groupUnit === 'days') {
            jkStandard = jkStandard / 24;
            jkActual = jkActual / 24;
          }

          const deviation = jkActual - jkStandard;
          
          // Count problematic routes (on-time < critical threshold)
          let problematicRoutes = 0;
          stats.routePerformance.forEach(routeStats => {
            if (routeStats.total === 0) return;
            const routeOnTime = (routeStats.onTime / routeStats.total) * 100;
            if (routeOnTime <= criticalThreshold) {
              problematicRoutes++;
            }
          });
          
          // Determine status based on thresholds
          let status: 'compliant' | 'warning' | 'critical';
          if (onTimePercentage >= warningThreshold) {
            status = 'compliant';
          } else if (onTimePercentage > criticalThreshold) {
            status = 'warning';
          } else {
            status = 'critical';
          }

          result.push({
            carrier,
            product,
            routes: stats.routes.size,
            totalSamples: stats.total,
            unit: groupUnit,
            jkStandard,
            jkActual,
            deviation,
            onTimePercentage,
            problematicRoutes,
            status
          });
        });

        setData(result);
      } catch (err) {
        setError(err as Error);
      } finally {
        setLoading(false);
      }
    }

    fetchData();
  }, [activeAccountId, filters.dateFrom, filters.dateTo, filters.routeType, filters.originCity, filters.destinationCity, filters.carrier, filters.product, accountTimezone]);

  return { data, loading, error, globalWarningThreshold, globalCriticalThreshold };
}
