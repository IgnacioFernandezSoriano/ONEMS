import { Button } from '@/components/common/Button'

interface CSVHandlerProps {
  onImport: (file: File) => Promise<void>
  onDownloadTemplate: () => void
}

export function CSVHandler({ onImport, onDownloadTemplate }: CSVHandlerProps) {
  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (!file) return

    try {
      await onImport(file)
      e.target.value = '' // Reset input
    } catch (error: any) {
      alert(`Import error: ${error.message}`)
    }
  }

  return (
    <div className="flex gap-4 items-center">
      <div>
        <label className="cursor-pointer">
          <input
            type="file"
            accept=".csv"
            onChange={handleFileChange}
            className="hidden"
            id="csv-upload"
          />
          <span className="inline-flex items-center px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 cursor-pointer">
            Import CSV
          </span>
        </label>
      </div>

      <Button variant="secondary" onClick={onDownloadTemplate}>
        Download CSV Template
      </Button>
    </div>
  )
}
