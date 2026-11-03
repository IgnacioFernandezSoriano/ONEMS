import { useTranslation } from '@/hooks/useTranslation'

interface TooltipBlockProps {
  titleKey: string
  descKey: string
  interpKey: string
  useKey: string
}

// eslint-disable-next-line react-refresh/only-export-components
function TooltipBlock({ titleKey, descKey, interpKey, useKey }: TooltipBlockProps) {
  const { t } = useTranslation()
  return (
    <div className="space-y-2">
      <p className="font-semibold">{t(titleKey)}</p>
      <p><span className="font-medium">{t('hc.territory_equity_tooltips.description_label')}</span> {t(descKey)}</p>
      <p><span className="font-medium">{t('hc.territory_equity_tooltips.interpretation_label')}</span> {t(interpKey)}</p>
      <p><span className="font-medium">{t('hc.territory_equity_tooltips.regulatory_use_label')}</span> {t(useKey)}</p>
    </div>
  )
}

export const tooltips = {
  serviceEquityIndex: (
    <TooltipBlock
      titleKey="hc.territory_equity_tooltips.service_equity_index_title"
      descKey="hc.territory_equity_tooltips.service_equity_index_desc"
      interpKey="hc.territory_equity_tooltips.service_equity_index_interp"
      useKey="hc.territory_equity_tooltips.service_equity_index_use"
    />
  ),

  populationWeightedCompliance: (
    <TooltipBlock
      titleKey="hc.territory_equity_tooltips.pop_weighted_title"
      descKey="hc.territory_equity_tooltips.pop_weighted_desc"
      interpKey="hc.territory_equity_tooltips.pop_weighted_interp"
      useKey="hc.territory_equity_tooltips.pop_weighted_use"
    />
  ),

  underservedCities: (
    <TooltipBlock
      titleKey="hc.territory_equity_tooltips.underserved_title"
      descKey="hc.territory_equity_tooltips.underserved_desc"
      interpKey="hc.territory_equity_tooltips.underserved_interp"
      useKey="hc.territory_equity_tooltips.underserved_use"
    />
  ),

  citizensAffected: (
    <TooltipBlock
      titleKey="hc.territory_equity_tooltips.citizens_affected_title"
      descKey="hc.territory_equity_tooltips.citizens_affected_desc"
      interpKey="hc.territory_equity_tooltips.citizens_affected_interp"
      useKey="hc.territory_equity_tooltips.citizens_affected_use"
    />
  ),

  topBestServed: (
    <TooltipBlock
      titleKey="hc.territory_equity_tooltips.best_served_title"
      descKey="hc.territory_equity_tooltips.best_served_desc"
      interpKey="hc.territory_equity_tooltips.best_served_interp"
      useKey="hc.territory_equity_tooltips.best_served_use"
    />
  ),

  topWorstServed: (
    <TooltipBlock
      titleKey="hc.territory_equity_tooltips.worst_served_title"
      descKey="hc.territory_equity_tooltips.worst_served_desc"
      interpKey="hc.territory_equity_tooltips.worst_served_interp"
      useKey="hc.territory_equity_tooltips.worst_served_use"
    />
  ),

  inboundOutboundChart: (
    <TooltipBlock
      titleKey="hc.territory_equity_tooltips.in_out_chart_title"
      descKey="hc.territory_equity_tooltips.in_out_chart_desc"
      interpKey="hc.territory_equity_tooltips.in_out_chart_interp"
      useKey="hc.territory_equity_tooltips.in_out_chart_use"
    />
  ),

  cityTable: (
    <TooltipBlock
      titleKey="hc.territory_equity_tooltips.city_table_title"
      descKey="hc.territory_equity_tooltips.city_table_desc"
      interpKey="hc.territory_equity_tooltips.city_table_interp"
      useKey="hc.territory_equity_tooltips.city_table_use"
    />
  ),

  regionalChart: (
    <TooltipBlock
      titleKey="hc.territory_equity_tooltips.regional_chart_title"
      descKey="hc.territory_equity_tooltips.regional_chart_desc"
      interpKey="hc.territory_equity_tooltips.regional_chart_interp"
      useKey="hc.territory_equity_tooltips.regional_chart_use"
    />
  ),

  regionalTable: (
    <TooltipBlock
      titleKey="hc.territory_equity_tooltips.regional_table_title"
      descKey="hc.territory_equity_tooltips.regional_table_desc"
      interpKey="hc.territory_equity_tooltips.regional_table_interp"
      useKey="hc.territory_equity_tooltips.regional_table_use"
    />
  ),

  treemap: (
    <TooltipBlock
      titleKey="hc.territory_equity_tooltips.treemap_title"
      descKey="hc.territory_equity_tooltips.treemap_desc"
      interpKey="hc.territory_equity_tooltips.treemap_interp"
      useKey="hc.territory_equity_tooltips.treemap_use"
    />
  ),
};
