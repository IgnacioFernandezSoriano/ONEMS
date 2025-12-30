import { useState } from 'react'
import { Upload, Download, CheckCircle, AlertCircle, FileText } from 'lucide-react'

export default function TranslationManager() {
  const [uploading, setUploading] = useState(false)
  const [uploadStatus, setUploadStatus] = useState<{
    type: 'success' | 'error' | null
    message: string
  }>({ type: null, message: '' })

  const handleFileUpload = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0]
    if (!file) return

    setUploading(true)
    setUploadStatus({ type: null, message: '' })

    try {
      // Validate file type
      if (!file.name.endsWith('.csv')) {
        throw new Error('Please upload a CSV file')
      }

      // Read file content
      const text = await file.text()
      
      // Validate CSV structure
      const lines = text.split('\n')
      if (lines.length < 2) {
        throw new Error('CSV file is empty or invalid')
      }

      const header = lines[0].toLowerCase()
      const requiredColumns = ['key', 'en', 'es', 'fr', 'ar']
      const missingColumns = requiredColumns.filter(col => !header.includes(col))
      
      if (missingColumns.length > 0) {
        throw new Error(`CSV missing required columns: ${missingColumns.join(', ')}`)
      }

      // Count translations
      const translationCount = lines.length - 1 // Exclude header
      
      // Save to public/locales directory
      // In production, this would be handled by a backend API
      // For now, we'll create a download link for the user to manually place the file
      
      // Extract language-specific CSVs
      const languages = ['en', 'es', 'fr', 'ar']
      const headerParts = lines[0].split(',')
      const keyIdx = headerParts.findIndex(h => h.trim().toLowerCase() === 'key')
      
      for (const lang of languages) {
        const langIdx = headerParts.findIndex(h => h.trim().toLowerCase() === lang)
        if (langIdx === -1) continue

        let langCSV = 'key,translation,context\n'
        
        for (let i = 1; i < lines.length; i++) {
          const parts = lines[i].split(',')
          const key = parts[keyIdx]?.trim()
          const translation = parts[langIdx]?.trim()
          const context = parts[headerParts.findIndex(h => h.trim().toLowerCase() === 'context')]?.trim() || ''
          
          if (key && translation) {
            langCSV += `${key},${translation},${context}\n`
          }
        }

        // Create download for this language
        const blob = new Blob([langCSV], { type: 'text/csv;charset=utf-8;' })
        const url = URL.createObjectURL(blob)
        const link = document.createElement('a')
        link.href = url
        link.download = `${lang}.csv`
        link.click()
        URL.revokeObjectURL(url)
      }

      setUploadStatus({
        type: 'success',
        message: `Successfully processed ${translationCount} translations. Download the generated language files and place them in the public/locales/ directory.`
      })
    } catch (error) {
      setUploadStatus({
        type: 'error',
        message: error instanceof Error ? error.message : 'Failed to process CSV file'
      })
    } finally {
      setUploading(false)
      // Reset file input
      event.target.value = ''
    }
  }

  const downloadTemplate = () => {
    // In production, this would fetch the latest template from the server
    const link = document.createElement('a')
    link.href = '/translations_template.csv'
    link.download = 'translations_template.csv'
    link.click()
  }

  return (
    <div className="p-6 max-w-4xl mx-auto">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Translation Manager</h1>
        <p className="text-gray-600 mt-2">
          Upload translated CSV files to update application translations
        </p>
      </div>

      {/* Instructions */}
      <div className="bg-blue-50 border border-blue-200 rounded-lg p-6 mb-6">
        <h2 className="text-lg font-semibold text-blue-900 mb-3 flex items-center gap-2">
          <FileText className="w-5 h-5" />
          How to Use
        </h2>
        <ol className="list-decimal list-inside space-y-2 text-blue-800">
          <li>Download the CSV template using the button below</li>
          <li>Translate the empty columns (es, fr, ar) in Excel or Google Sheets</li>
          <li>Save the file as CSV (UTF-8 encoding)</li>
          <li>Upload the translated CSV file here</li>
          <li>Download the generated language files</li>
          <li>Place the files in the <code className="bg-blue-100 px-1 rounded">public/locales/</code> directory</li>
        </ol>
      </div>

      {/* Download Template */}
      <div className="bg-white border border-gray-200 rounded-lg p-6 mb-6">
        <h2 className="text-lg font-semibold text-gray-900 mb-3">Step 1: Download Template</h2>
        <p className="text-gray-600 mb-4">
          Download the CSV template with all application strings to translate
        </p>
        <button
          onClick={downloadTemplate}
          className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
        >
          <Download className="w-4 h-4" />
          Download CSV Template
        </button>
      </div>

      {/* Upload Translated CSV */}
      <div className="bg-white border border-gray-200 rounded-lg p-6">
        <h2 className="text-lg font-semibold text-gray-900 mb-3">Step 2: Upload Translated CSV</h2>
        <p className="text-gray-600 mb-4">
          Upload your translated CSV file to generate language-specific files
        </p>
        
        <div className="border-2 border-dashed border-gray-300 rounded-lg p-8 text-center">
          <Upload className="w-12 h-12 text-gray-400 mx-auto mb-4" />
          <label className="cursor-pointer">
            <span className="text-blue-600 hover:text-blue-700 font-medium">
              Click to upload
            </span>
            <span className="text-gray-600"> or drag and drop</span>
            <input
              type="file"
              accept=".csv"
              onChange={handleFileUpload}
              disabled={uploading}
              className="hidden"
            />
          </label>
          <p className="text-sm text-gray-500 mt-2">CSV file only</p>
        </div>

        {/* Upload Status */}
        {uploadStatus.type && (
          <div
            className={`mt-4 p-4 rounded-lg flex items-start gap-3 ${
              uploadStatus.type === 'success'
                ? 'bg-green-50 border border-green-200'
                : 'bg-red-50 border border-red-200'
            }`}
          >
            {uploadStatus.type === 'success' ? (
              <CheckCircle className="w-5 h-5 text-green-600 flex-shrink-0 mt-0.5" />
            ) : (
              <AlertCircle className="w-5 h-5 text-red-600 flex-shrink-0 mt-0.5" />
            )}
            <p
              className={
                uploadStatus.type === 'success' ? 'text-green-800' : 'text-red-800'
              }
            >
              {uploadStatus.message}
            </p>
          </div>
        )}

        {uploading && (
          <div className="mt-4 text-center">
            <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
            <p className="text-gray-600 mt-2">Processing CSV file...</p>
          </div>
        )}
      </div>

      {/* Current Languages */}
      <div className="bg-white border border-gray-200 rounded-lg p-6 mt-6">
        <h2 className="text-lg font-semibold text-gray-900 mb-3">Supported Languages</h2>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          {[
            { code: 'en', name: 'English', flag: '🇬🇧' },
            { code: 'es', name: 'Español', flag: '🇪🇸' },
            { code: 'fr', name: 'Français', flag: '🇫🇷' },
            { code: 'ar', name: 'العربية', flag: '🇸🇦' }
          ].map(lang => (
            <div
              key={lang.code}
              className="border border-gray-200 rounded-lg p-4 text-center"
            >
              <div className="text-3xl mb-2">{lang.flag}</div>
              <div className="font-medium text-gray-900">{lang.name}</div>
              <div className="text-sm text-gray-500">{lang.code.toUpperCase()}</div>
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
