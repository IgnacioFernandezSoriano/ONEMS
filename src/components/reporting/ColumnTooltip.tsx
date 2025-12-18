import { SmartTooltip } from '@/components/common/SmartTooltip';

interface ColumnTooltipProps {
  content: string | React.ReactNode;
}

export function ColumnTooltip({ content }: ColumnTooltipProps) {
  return <SmartTooltip content={content} />;
}
