//
//  BeagleHRV.swift
//  BEAGLE HRV - 100% Otimizado, Leve, Roda no Watch + iPhone + Mac
//  Zero Lag, Zero Bateria Extra
//

import HealthKit
import Combine
import os.log

@Observable
final class BeagleHRV {
    static let shared = BeagleHRV()
    
    private let healthStore = HKHealthStore()
    private var hrvCancellable: AnyCancellable?
    
    var currentHRV: Double = 0.0
    var flowState: FlowState = .unknown
    
    enum FlowState: String {
        case flow = "FLOW"
        case stress = "STRESS"
        case normal = "NORMAL"
        case unknown = "UNKNOWN"
    }
    
    private init() {
        requestAuthorization()
        startHRVObserver()
    }
    
    private func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        
        let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let readTypes: Set = [hrvType]
        
        healthStore.requestAuthorization(toShare: nil, read: readTypes) { success, error in
            if success {
                os_log("HRV authorization granted")
            }
        }
    }
    
    private func startHRVObserver() {
        let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        
        let query = HKObserverQuery(sampleType: hrvType, predicate: nil) { [weak self] _, completionHandler, error in
            guard let self else { 
                completionHandler()
                return 
            }
            if error != nil { 
                completionHandler()
                return 
            }
            
            self.fetchLatestHRV { _ in
                completionHandler()
            }
        }
        
        healthStore.execute(query)
        healthStore.enableBackgroundDelivery(for: hrvType, frequency: .immediate) { _, _ in }
        
        // Backup timer (caso o observer falhe) - a cada 5 minutos
        hrvCancellable = Timer.publish(every: 300, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.fetchLatestHRV { _ in }
            }
    }
    
    private func fetchLatestHRV(completion: @escaping (Double) -> Void) {
        let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        let query = HKSampleQuery(sampleType: hrvType, predicate: nil, limit: 1, sortDescriptors: [sort]) { [weak self] _, samples, _ in
            guard let self else {
                completion(0.0)
                return
            }
            
            guard let sample = samples?.first as? HKQuantitySample else {
                completion(0.0)
                return
            }
            
            let hrv = sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
            DispatchQueue.main.async {
                self.currentHRV = hrv
                self.flowState = hrv > 80 ? .flow : (hrv < 50 ? .stress : .normal)
                
                // Manda pro BEAGLE via teu endpoint
                self.sendToBeagle(hrv: hrv, state: self.flowState.rawValue)
                completion(hrv)
            }
        }
        
        healthStore.execute(query)
    }
    
    private func sendToBeagle(hrv: Double, state: String) {
        let url = URL(string: "http://t560.local:9000/api/hrv")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "hrv": hrv,
            "state": state,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        URLSession.shared.dataTask(with: request).resume()
    }
}

