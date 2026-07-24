
import Foundation
import SwiftUI
import HealthKit
import Observation
import SwiftData
import Charts
import UserNotifications
import FamilyControls
import DeviceActivity
import ManagedSettings
import Combine





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
        
        steps = 0
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
    
    
    
    @AppStorage("water") private var water = 0
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
    
    @State private var infoSheet = false
    
    
    //for the walk
    @State private var shouldPresentSheet1 = false
    @State private var shouldPresentSheet2 = false
    @State private var shouldPresentSheet3 = false
    
    @State private var shouldPresentScreenTimeSheet = false
    
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

    @AppStorage("lastWalkDate") private var lastWalkDate: Double = 0
    @AppStorage("streak") private var streak = 6
    func completeDailyWalk() {
        let today = Calendar.current.startOfDay(for: Date())
        let lastDate = Date(timeIntervalSince1970: lastWalkDate)

        if Calendar.current.isDate(today, inSameDayAs: lastDate) {
            return
        }

        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today),
           Calendar.current.isDate(lastDate, inSameDayAs: yesterday) {

            streak += 1

        } else {

            streak = 0
        }

        lastWalkDate = today.timeIntervalSince1970
    }
    
    @State private var IsCoverShown = false
    

    
    @AppStorage("hour") var selectedHours = 2
    @AppStorage("minute") var selectedMinutes = 0
    @AppStorage("explain") var explained = false
    @State private var explainSheet = false
        
    @Environment(\.dismiss) var dismiss
    @State private var healthStore = HealthStore()
    
    
    struct InfoRow: View {
        let icon: String
        let color: Color
        let text: String

        var body: some View {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 28)

                Text(text)

                Spacer()
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
    
    
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

                    Image(.a)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 350, height: 450)
                    
                }
                else if water < 351 {
                    Text("Tree has grown, make it larger!")                        .font(.system(size: 20))                         .padding(.horizontal, 40)


                    Image(.b)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 350, height: 450)
                }
                else if water < 601 {
                    Text("Nice! Keep going!")                        .font(.system(size: 20))                         .padding(.horizontal, 40)


                    Image(.c)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 350, height: 450)
                    
                }
                else if water < 1001 {
                    Text("You're on the way!")                        .font(.system(size: 20))                         .padding(.horizontal, 40)


                    Image(.d)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 350, height: 450)
                    
                }
                else if water < 1501 {
                    Text("That's pretty good!")                        .font(.system(size: 20))                         .padding(.horizontal, 40)


                    Image(.e)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 350, height: 450)
                    
                }
                else if water < 2751 {
                    Text("Come on!")                        .font(.system(size: 20))                         .padding(.horizontal, 40)


                    Image(.f)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 350, height: 450)
                    
                }
                else if water <  4001 {
                    Text("Oh yeah!")                        .font(.system(size: 20))                        .padding(.horizontal, 40)


                    Image(.g)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 350, height: 450)
                    
                }
                else {
                    Text("Hot damn!")                        .font(.system(size: 20))                        .padding(.horizontal, 40)


                    Image(.h)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 350, height: 450)
                    
                }
                HStack {
                    //screen time
                    Button (" Screen Time ") {
                        shouldPresentScreenTimeSheet.toggle()
                    }
                    .font(.title2)
                    .accentColor(.red)
                    .controlSize(.extraLarge)
                    .sheet(isPresented:$shouldPresentScreenTimeSheet) { }
                    content :{
                        Form {
                            Section {
                                Text("Set your screen time goal")
                                HStack {
                                    
                                    Picker("Hours", selection: $selectedHours) {
                                        ForEach(0...4, id: \.self) { hour in
                                            Text("\(hour) h")
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                    
                                    Picker("Minutes", selection: $selectedMinutes) {
                                        ForEach([0, 15, 30, 45], id: \.self) { minute in
                                            Text("\(minute) min")
                                        }
                                    }
                                    .pickerStyle(.wheel)
                                }.formStyle(.columns)
                            }
                            Section {
                                Text("  Did you reach your goal?")
                                HStack {
                                    Button (" Yes ") {
                                        showAlert = true
                                        water += 25
                                    }
                                    .padding()
                                                        .background(.blue)
                                                        .foregroundStyle(.white)
                                                        .clipShape(.rect(cornerRadius: 10))
                                    .alert("Good job! You have \(water) now.", isPresented: $showAlert) {
                                        Button("Close") {
                                            showAlert = false
                                            shouldPresentScreenTimeSheet.toggle()
                                        
                                    }
                                    }
                                    .padding()
                                    Button (" No ") {
                                        showAlert = true
                                    }
                                    .padding()
                                                        .background(.red)
                                                        .foregroundStyle(.white)
                                                        .clipShape(.rect(cornerRadius: 10))
                                    .alert("Try again tomorrow! You can do it!", isPresented: $showAlert) {
                                        Button("Close") {
                                            showAlert = false
                                            shouldPresentScreenTimeSheet.toggle()
                                        
                                    }
                                    }
                                    
                                }
                                Button ("Close") {
                                    shouldPresentScreenTimeSheet.toggle()
                                }
                            }
                            .frame(height: 120)
                        }
                    }
                    //button for bedtime
                    Button (" Sleep Hours ") {
                        shouldPresentSleepSheet.toggle()
                    }
                    .font(.title2)
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
                                                print("Done!")
                                            } else if let error {
                                                print(error.localizedDescription)
                                            }
                                        }
                                    }
                                    .font(.title3)
                                    Text("From when to when did you sleep?")
                                    
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
                                    
                                    Button ("Collect rewards") {
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
                                                
                                    
//                                    Chart(last7Days) { entry in
//                                        BarMark(
//                                            x: .value("Day", entry.date, unit: .day),
//                                            y: .value("Hours", entry.hours)
//                                        )
//                                    }
//                                    .frame(height: 250)
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
                            Text("Take a moment and keep your phone")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            
                            VStack(spacing: 16) {
                                InfoRow(icon: "tree.fill",
                                        color: .green,
                                        text: "The trees")

                                InfoRow(icon: "leaf.fill",
                                        color: .green,
                                        text: "The grass")

                                InfoRow(icon: "water.waves",
                                        color: .blue,
                                        text: "The water")

                                InfoRow(icon: "heart.fill",
                                        color: .red,
                                        text: "How you feel")

                                InfoRow(icon: "soccerball",
                                        color: .black,
                                        text: "Activities going on")

                                InfoRow(icon: "car.fill",
                                        color: .cyan,
                                        text: "The cars")
                            }
                            .padding()
                            .background(.thinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 25))
                            .shadow(radius: 10)
                        
                        
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
                            completeDailyWalk()
                        }
                        
                    }
                    //for the questions page
                    .sheet(isPresented:$shouldPresentSheet2) {
                    }
                    content: {
                        
                        NavigationStack{
                        VStack{
                            
                            Form{
                                Section(header: Text("Was the walk enjoyable? ")){
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
                                Section(header: Text("How do you feel after the walk? ")){
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
                                            if streak == 7 {
                                                    water += 50
                                                    streak = 0
                                                    showAlert = true
                                                } else {
                                                    shouldPresentSheet1 = false
                                                    shouldPresentSheet2 = false
                                                    shouldPresentSheet3 = false
                                                    healthStore.steps = 0
                                                }
                                            }
                                            .alert("7 Day Streak!", isPresented: $showAlert) {
                                                Button("OK") {
                                                    shouldPresentSheet1 = false
                                                    shouldPresentSheet2 = false
                                                    shouldPresentSheet3 = false
                                                    healthStore.steps = 0
                                                }
                                            } message: {
                                                Text("You achieved a 7 day streak! An extra 20 💧 has been added.")
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
        .accentColor(.green)
        .controlSize(.extraLarge)
        
        Button (" Info  ") {
infoSheet = true
        }
        .font(.title2)
        .padding()
        .background(.gray)
        .foregroundStyle(.white)
        .clipShape(.rect(cornerRadius: 10))
        .sheet(isPresented:$infoSheet) {
        } content:{
            VStack(spacing: 20) {
                NavigationStack{
                    Text("")
                    Text("Information")
                        .font(.title2)
                    Form {
                        
                        Section {
                            Text("Set your screen time goal and achieve it for water!")                                .font(.title3)

                        }
                        Section {
                            Text("Sleep for longer to gain more water!")                                .font(.title3)

                        }
                        Section {
                            Text("Walk for a while to gain water, and answer optional questions for additional water!")
                                .font(.title3)
                        }
                        Section {
                            Text("This will grow your tree!")                                .font(.title3)

                        }
                    }
                }
                Button("Close") {
                    infoSheet = false
                }
                .font(.title2)
                .padding()
                .background(.gray)
                .foregroundStyle(.white)
                .clipShape(.rect(cornerRadius: 10))

            }
                
            
        }
                

//        .onAppear {
//                    if explained == false {
//                        showAlert = true
//                    }
//                }
//                .alert("Welcome!", isPresented: $showAlert) {
//                    Button("👍") {
//                        explained = true
//                    }
//                } message: {
//                    Text("""
//                    Grow your tree by sleeping well, staying under your screen time goals and completing walks.
//                    Check in every day to keep your progress going!
//                    """)
//                }
    }
}


#Preview {
    ContentView()
}
