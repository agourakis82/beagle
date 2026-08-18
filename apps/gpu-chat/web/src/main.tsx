import { createRoot } from 'react-dom/client'
import 'highlight.js/styles/github-dark.css'
import './styles.css'
import { App } from './App.js'

createRoot(document.getElementById('root')!).render(<App />)
