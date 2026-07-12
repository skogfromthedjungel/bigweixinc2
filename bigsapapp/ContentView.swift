
import Foundation
import SwiftUI
import HealthKit
import Observation
import SwiftData
import Charts
import UserNotifications

@Model
class SleepEntry {
    var date: Date
    var hours: Double

    init(date: Date = .now, hours: Double) {
        self.date = date
        self.hours = hours
    }
}

enum HealthError: Error {
    case healthDataNotAvailable
}

//for healthstore
@Observable
class HealthStore{
    
    var steps: Int=0
    var healthStore: HKHealthStore?
    var lastError: Error?
    // for healthstore
    init(){
        if HKHealthStore.isHealthDataAvailable(){
            healthStore = HKHealthStore() 
        }else {
            lastError = HealthError.healthDataNotAvailable
        }
    }
    func calculateSteps() async throws {
        
        steps = -20000
        guard let healthStore = self.healthStore else { return }
        
        let calendar = Calendar(identifier: .gregorian)
        let startDate = calendar.startOfDay(for: Date())
        let endDate = Date()
        
        let stepType = HKQuantityType(.stepCount)
        let everyDay = DateComponents(day:1)
        let thisWeek = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let stepsThisWeek = HKSamplePredicate.quantitySample(type: stepType, predicate: thisWeek)
        
        let sumOfStepsQuery = HKStatisticsCollectionQueryDescriptor(predicate: stepsThisWeek, options: .cumulativeSum, anchorDate: endDate, intervalComponents: everyDay)
        
        let stepsCount = try await sumOfStepsQuery.result(for: healthStore)
        
        
        stepsCount.enumerateStatistics(from: startDate, to: endDate) { statistics, stop in
            let count = statistics.sumQuantity()?.doubleValue(for: .count())
            let step = Int(count ?? 0)
            if step > 0 {
                self.steps = step
            }
        }
        
    }
    
    func requestAuthorization() async {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier.stepCount) else { return }
        guard let healthStore = self.healthStore else{ return }
        
        do{
            try await healthStore.requestAuthorization( toShare:[], read: [stepType])
        } catch{
            lastError = error
        }
        
    }
}



struct ContentView: View {
    
    
    
    @AppStorage("water") private var water = 200
    @AppStorage("dates") private var savedDate = Date.now.addingTimeInterval(86400)
    
    //for sleep
    
    func scheduleWakeNotification() {

        let content = UNMutableNotificationContent()
        content.title = "Good Morning!"
        content.body = "Tap here to add your sleep time"
        content.sound = .default

        let calendar = Calendar.current

        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: wakeTime
        )

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "wakeNotification",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print(error.localizedDescription)
            }
        }
    }
    
    @Environment(\.modelContext) private var context
    
    let sleepType = HKObjectType.categoryType(
        forIdentifier: .sleepAnalysis
    )!

    @Query(sort: \SleepEntry.date)
    private var sleepEntries: [SleepEntry]
    

    @AppStorage("bed") private var bedtime = Date()
    @AppStorage("bed2") private var wakeTime = Date().addingTimeInterval(8 * 3600)

    
    
    var last7Days: [SleepEntry] {
        let calendar = Calendar.current
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: .now)!

        return sleepEntries.filter {
            $0.date >= calendar.startOfDay(for: sevenDaysAgo)
        }
    }
    
    
    
       var sleepHours: Double {
           let seconds = wakeTime.timeIntervalSince(bedtime)

           if seconds >= 0 {
               return seconds / 3600
           } else {
               return (seconds + 24 * 3600) / 3600
           }
       }
    
    @State private var shouldPresentSleepSheet = false
    
    
    //for the walk
    @State private var shouldPresentSheet1 = false
    @State private var shouldPresentSheet2 = false
    @State private var shouldPresentSheet3 = false
    
    @State private var showAlert = false
    @State private var navigateToNextPage = false
    @State private var showButton = false
    
    @State private var question1: String = ""
    @State private var question2: String = ""
    @State private var question3: String = ""
    @State private var question4: String = ""
    @State private var question5: String = ""
    @State private var question6: String = ""
    
    @State private var fill1 = false
    @State private var fill2 = false
    @State private var fill3 = false
    @State private var fill4 = false
    @State private var fill5 = false
    @State private var fill6 = false
    
    
    
    @State private var IsCoverShown = false
    
    @Environment(\.dismiss) var dismiss
    @State private var healthStore = HealthStore()
    
    
    
    var body: some View {
        NavigationStack{
            VStack {
                
                HStack {
                    //water display
                    let changedWater = water - 50
                    
                    if savedDate < Date() {
                        Text("💧\(changedWater)")
                            .frame(width: 300, height: 30, alignment: .topLeading)
                            .font(.system(size: 24))
                    } else {
                        Text("💧\(water) ")
                            .frame(width: 300, height: 30, alignment: .topLeading)
                            .font(.system(size: 24))
                            
                    }
                }
                
               
                        
                
                //tree image
                if water < 101 {
                    Text("Tree hasn't sprouted, go on a walk to grow it!")
                        .font(.system(size: 20))
                        .padding(.horizontal, 40)

                    Image(.dirt)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 350, height: 450)
                    
                }
                else if water < 351 {
                    Text("Tree has grown, make it larger!")                        .font(.system(size: 20))                         .padding(.horizontal, 40)


                    Image(.sapling)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 350, height: 450)
                }
                else if water < 601 {
                    Text("Nice! Keep going!")                        .font(.system(size: 20))                         .padding(.horizontal, 40)


                    Image(.supersmall)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 350, height: 450)
                    
                }
                else if water < 1001 {
                    Text("You're on the way!")                        .font(.system(size: 20))                         .padding(.horizontal, 40)


                    Image(.smallt)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 350, height: 450)
                    
                }
                else if water < 1501 {
                    Text("That's pretty good!")                        .font(.system(size: 20))                         .padding(.horizontal, 40)


                    Image(.firstmid)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 350, height: 450)
                    
                }
                else if water < 2751 {
                    Text("Come on!")                        .font(.system(size: 20))                         .padding(.horizontal, 40)


                    Image(.secondmid)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 350, height: 450)
                    
                }
                else if water <  4001 {
                    Text("Oh yeah!")                        .font(.system(size: 20))                        .padding(.horizontal, 40)


                    Image(.thirdbig)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 350, height: 450)
                    
                }
                else if water < 5671 {
                    Text("Almost there!")                        .font(.system(size: 20))                        .padding(.horizontal, 40)


                    Image(.fourbig)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 350, height: 450)
                    
                }
                else {
                    Text("Hot damn!")                        .font(.system(size: 20))                        .padding(.horizontal, 40)


                    Image(.bigboy)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 350, height: 450)
                    
                }
//                TabView {
//                        
//                        Tab("See Cat", systemImage: "eyes") {
//SleepView()
//                        }
//
//                        Tab("Pop-up Cat", systemImage: "inset.filled.bottomhalf.rectangle") {
//                            Text("Pop-up Cat")
//                    }
//                }
                HStack {
                    //button for bedtime
                    Button (" Set Hours ") {
                        shouldPresentSleepSheet.toggle()
                    }
                    .font(.title2)
                    .buttonStyle(.borderedProminent)
                    .accentColor(.blue)
                    .controlSize(.extraLarge)
                    .sheet(isPresented:$shouldPresentSleepSheet) {
                    } content:{
                        VStack(spacing: 20) {
                            
                            NavigationStack {
                                Form {
                                    
                                    Button ("Enable Notifications") {
                                        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { success, error in
                                            if success {
                                                print("All set!")
                                            } else if let error {
                                                print(error.localizedDescription)
                                            }
                                        }
                                    }
                                    .font(.title3)
                                    
                                    DatePicker(
                                                        "Bedtime",
                                                        selection: $bedtime,
                                                        displayedComponents: .hourAndMinute
                                                    )

                                                    DatePicker(
                                                        "Wake Up Time",
                                                        selection: $wakeTime,
                                                        displayedComponents: .hourAndMinute
                                                    )
                                    
                                    Button ("Set your sleep time") {
                                        water += Int(sleepHours)
                                        water += Int(sleepHours)
                                        
                                        showAlert = true
                                    }
                                    .alert("You have \(water) now!                        Make sure to log your sleep again tomorrow!", isPresented: $showAlert) {
                                        Button("Close") {
                                            showAlert = false
                                            shouldPresentSleepSheet.toggle()
                                        }
                                    }
                                    

                                                    Section("Sleep") {
                                                        Text("\(sleepHours, specifier: "%.1f") hours")
                                                            .font(.title2)
                                                            .bold()
                                                    }
                                                
                                    
                                    Chart(last7Days) { entry in
                                        BarMark(
                                            x: .value("Day", entry.date, unit: .day),
                                            y: .value("Hours", entry.hours)
                                        )
                                    }
                                    .frame(height: 250)
                                    Button (" Go Back ") {
                                        shouldPresentSleepSheet.toggle()
                                    }
                                }
                                .navigationTitle("Sleep Tracker")
                            }
                            
                        }
                    }
                        
                
//for walk
                Button (" Start a Walk ")
                {
                    savedDate = Date.now.addingTimeInterval(1296000)
                    shouldPresentSheet1.toggle()
                }
                .sheet(isPresented: $shouldPresentSheet1) {
                } content: {
                        VStack(spacing: 20) {
                            Text("")
                            
                                Text("The trees 🌲")
                                Text("The grass 🌿")
                                Text("The water 🌊")
                                Text("How you feel ♥️")
                                Text("Activities going on ⚽")
                                Text("The cars 🚘")
                            
                            .font(.system(size: 24))
                        
                        
                            if showButton {
                                Button(action: {
                                    showAlert = true
                                }) {
                                    Text("Next page")
                                        .font(.title2)
                                }
                            
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else {
                            Spacer()
                                .frame(height: 20)
                        }
                    }
                    .padding()
                    .task {
                        try? await Task.sleep(nanoseconds: 500)
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                            showButton = true
                        }
                    }
                   
                    .alert("Are you sure you want to continue to the next page?", isPresented: $showAlert) {
                        Button("Cancel", role:  .cancel) { }
                        Button("Continue") {
                            showAlert = false
                            shouldPresentSheet2 = true
                        }
                        
                    }
                    //for the questions page
                    .sheet(isPresented:$shouldPresentSheet2) {
                    }
                    content: {
                        
                        NavigationStack{
                        VStack{
                            
                            Form{
                                Section(header: Text("Was the walk enjoyable?: ")){
                                    TextField(text: $question1, prompt: Text("Optional")) {
                                        Text("question1")
                                        
                                    }  .onSubmit {
                                    }
                                }
                                Section(header: Text("What were the surroundings like?  ")){
                                    TextField(text: $question2, prompt: Text("Optional")) {
                                        Text("question2")
                                    }              .onSubmit {
                                        
                                    }
                                    
                                }
                                Section(header: Text("What was the most interesting thing on your walk? ")){
                                    TextField(text: $question3, prompt: Text("Optional")) {
                                        Text("question3")
                                        
                                    } .onSubmit {
                                        
                                        
                                    }
                                }
                                Section(header: Text("How do you feel after the walk?: ")){
                                    TextField(text: $question4, prompt: Text("0ptional")) {
                                        Text("question4")
                                    } .onSubmit {
                                        
                                    }
                                    
                                }
                                
                                
                                Button("Collect Rewards") {
                                    
                                    Task {
                                        await healthStore.requestAuthorization()
                                        do{
                                            try await healthStore.calculateSteps()
                                        } catch{
                                            print(error)
                                        }
                                        
                                        shouldPresentSheet3 = true
                                        if !question1.isEmpty {
                                            water += 10
                                        }
                                        if !question2.isEmpty {
                                            water += 15
                                        }
                                        if !question3.isEmpty {
                                            water += 15
                                        }
                                        if !question4.isEmpty {
                                            water += 15
                                        }
                                        if !question5.isEmpty {
                                            water += 15
                                        }
                                        if !question6.isEmpty {
                                            water += 10
                                        }
                                        
                                        water += healthStore.steps/200
                                        question1 = ""
                                        question2 = ""
                                        question3 = ""
                                        question4 = ""
                                        question5 = ""
                                        question6 = ""
                                    }
                                }
                            } .navigationTitle("Your Walk")
                                
                                //button for finishing page
                                .sheet(isPresented:$shouldPresentSheet3) {
                                } content: {
                                    VStack(spacing:90){
                                        Spacer()
                                        Text("Good Job!")
                                            .bold()
                                            .font(.largeTitle)
                                        HStack{
                                            
                                            Text("\(healthStore.steps) steps")
                                                .font(.system(size: 25))
                                        }
                                        HStack{
                                            
                                            Text("Total water: \(water)💧")
                                                .font(.system(size: 48))
                                        }
                                        Spacer()
                                        Button("Back to Home Page"){
                                            shouldPresentSheet1 = false
                                            shouldPresentSheet2 = false
                                            shouldPresentSheet3 = false
                                            healthStore.steps = 0
                                        }
                                        .padding()
                                        .task {
                                            await healthStore.requestAuthorization()
                                            do{
                                                try await healthStore.calculateSteps()
                                            } catch{
                                                print(error)
                                            }
                                        }
                                    }
                                }
                            }
                            }
                        }
                    }
                } 
            }
        }
        .font(.title2)
        .buttonStyle(.borderedProminent)
        .accentColor(.green)
        .controlSize(.extraLarge)
    } 
}


#Preview {
    ContentView()
}
