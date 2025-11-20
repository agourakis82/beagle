//! BEAGLE Apple Watch App - HRV Monitoring + Voice Control

import SwiftUI
import HealthKit

@main
struct BeagleWatchApp: App {
    @StateObject private var assistant = BeagleWatchAssistant.shared
    
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 20) {
                Text("BEAGLE")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.cyan)
                
                Text("HRV: \(Int(assistant.hrvValue))ms")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(assistant.flowState == "FLOW" ? .green : .red)
                
                Text(assistant.flowState)
                    .font(.system(size: 18))
                    .foregroundColor(.gray)
                
                Button(action: {
                    assistant.toggleListening()
                }) {
                    Image(systemName: assistant.isListening ? "mic.fill" : "mic.slash.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                        .frame(width: 80, height: 80)
                        .background(assistant.isListening ? Color.red : Color.green)
                        .clipShape(Circle())
                }
            }
            .padding()
        }
    }
}

@MainActor
class BeagleWatchAssistant: ObservableObject {
    static let shared = BeagleWatchAssistant()
    
    @Published var isListening = false
    @Published var hrvValue: Double = 0
    @Published var flowState: String = "UNKNOWN"
    
    private let healthStore = HKHealthStore()
    
    init() {
        requestPermissions()
        startHRVMonitoring()
    }
    
    func requestPermissions() {
        let types: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!
        ]
        
        healthStore.requestAuthorization(toShare: nil, read: types) { _, _ in }
    }
    
    func startHRVMonitoring() {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return
        }
        
        let observer = HKObserverQuery(sampleType: hrvType, predicate: nil) { [weak self] query, completionHandler, error in
            guard let self = self else { return }
            
            self.fetchLatestHRV { hrv in
                Task { @MainActor in
                    self.hrvValue = hrv
                    self.flowState = hrv > 80 ? "FLOW" : "STRESS"
                }
            }
            
            completionHandler()
        }
        
        healthStore.execute(observer)
        healthStore.enableBackgroundDelivery(for: hrvType, frequency: .immediate) { _, _ in }
    }
    
    func fetchLatestHRV(completion: @escaping (Double) -> Void) {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            completion(0)
            return
        }
        
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: hrvType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, _ in
            guard let sample = samples?.first as? HKQuantitySample else {
                completion(0)
                return
            }
            
            let hrv = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
            completion(hrv)
        }
        
        healthStore.execute(query)
    }
    
    func toggleListening() {
        isListening.toggle()
        // TODO: Integrar com Speech Recognition
    }
}
