import { Info } from 'lucide-react';

interface ColumnTooltipProps {
  content: string | React.ReactNode;
}

export function ColumnTooltip({ content }: ColumnTooltipProps) {
  return (
    <div className="group relative inline-block">
      <Info className="w-3 h-3 text-gray-400 cursor-help" />
      <div className="invisible group-hover:visible absolute z-10 w-64 p-2 bg-gray-900 text-white text-xs rounded shadow-lg -right-2 top-6">
        <div className="absolute -top-1 right-4 w-2 h-2 bg-gray-900 transform rotate-45"></div>
        {typeof content === 'string' ? <p>{content}</p> : content}
      </div>
    </div>
  );
}
