import SwiftUI
import HealthKit
import Observation
import SwiftData
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

enum HealthError: Error { case healthDataNotAvailable }

private enum NaturePalette {
    static let a = Color(red: 0.08, green: 0.31, blue: 0.19)
    static let b = Color(red: 0.19, green: 0.48, blue: 0.27)
    static let c = Color(red: 0.75, green: 0.86, blue: 0.72)
    static let d = Color(red: 0.94, green: 0.98, blue: 0.93)
    static let e = Color(red: 0.99, green: 0.99, blue: 0.96)
    static let f = Color(red: 0.45, green: 0.31, blue: 0.20)
}

private struct NatureCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(.white.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(NaturePalette.c.opacity(0.55), lineWidth: 1)
            }
            .shadow(color: NaturePalette.a.opacity(0.09), radius: 16, y: 7)
    }
}

private extension View {
    func natureCard() -> some View { modifier(NatureCard()) }
}

@Observable
class HealthStore {
    var steps: Int = 0
    var healthStore: HKHealthStore?
    var lastError: Error?

    init() {
        if HKHealthStore.isHealthDataAvailable() {
            healthStore = HKHealthStore()
        } else {
            lastError = HealthError.healthDataNotAvailable
        }
    }

    func calculateSteps() async throws {
        //adjusts actual step count
        steps = 0
        guard let healthStore = self.healthStore else { return }
        let calendar = Calendar(identifier: .gregorian)
        let startDate = calendar.startOfDay(for: Date())
        let endDate = Date()
        let stepType = HKQuantityType(.stepCount)
        let everyDay = DateComponents(day: 1)
        let thisWeek = HKQuery.predicateForSamples(withStart: startDate, end: endDate)
        let stepsThisWeek = HKSamplePredicate.quantitySample(type: stepType, predicate: thisWeek)
        let query = HKStatisticsCollectionQueryDescriptor(predicate: stepsThisWeek, options: .cumulativeSum, anchorDate: endDate, intervalComponents: everyDay)
        let stepsCount = try await query.result(for: healthStore)

        stepsCount.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
            let step = Int(statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            if step > 0 { self.steps = step }
        }
    }

    func requestAuthorization() async {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount), let healthStore else { return }
        do {
            try await healthStore.requestAuthorization(toShare: [], read: [stepType])
        } catch {
            lastError = error
        }
    }
}

struct ContentView: View {
    @AppStorage("water") private var water = 0
    @AppStorage("dates") private var savedDate = Date.now.addingTimeInterval(86400)
    @Environment(\.modelContext) private var context
    @Query(sort: \SleepEntry.date) private var sleepEntries: [SleepEntry]
    @AppStorage("bed") private var bedtime = Date()
    @AppStorage("bed2") private var wakeTime = Date().addingTimeInterval(8 * 3600)
    @State private var shouldPresentSleepSheet = false
    @State private var infoSheet = false
    @State private var shouldPresentSheet1 = false
    @State private var shouldPresentSheet2 = false
    @State private var shouldPresentSheet3 = false
    @State private var shouldPresentScreenTimeSheet = false

    @State private var presentWalkQuestionsAfterIntro = false
    @State private var showAlert = false
    @State private var showButton = false
    @State private var question1 = ""
    @State private var question2 = ""
    @State private var question3 = ""
    @State private var question4 = ""
    @State private var question5 = ""
    @State private var question6 = ""
    @AppStorage("lastWalkDate") private var lastWalkDate: Double = 0
    @AppStorage("streak") private var streak = 6
    @AppStorage("hour") private var selectedHours = 2
    @AppStorage("minute") private var selectedMinutes = 0
    @State private var healthStore = HealthStore()

    var last7Days: [SleepEntry] {
        let calendar = Calendar.current
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: .now)!
        return sleepEntries.filter { $0.date >= calendar.startOfDay(for: sevenDaysAgo) }
    }

    var sleepHours: Double {
        let seconds = wakeTime.timeIntervalSince(bedtime)
        return seconds >= 0 ? seconds / 3600 : (seconds + 24 * 3600) / 3600
    }


    private var treeMessage: String {
        switch water {
        case ..<101: "Tree hasn't sprouted yet."
        case ..<301: "Tree has grown, make it larger!"
        case ..<801: "Nice! Keep going!"
        case ..<1501: "You're on the way!"
        case ..<2501: "That's pretty good!"
        case ..<3701: "Come on!"
        case ..<5001: "Oh yeah!"
        default: "Hot damn!"
        }
    }

    private var treeImage: Image {
        switch water {
        case ..<101: Image(.a)
        case ..<301: Image(.b)
        case ..<801: Image(.c)
        case ..<1501: Image(.d)
        case ..<2501: Image(.e)
        case ..<3701: Image(.f)
        case ..<5001: Image(.g)
        default: Image(.h)
        }
    }

    func scheduleWakeNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Good Morning!"
        content.body = "Tap here to add your sleep time"
        content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: wakeTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "wakeNotification", content: content, trigger: trigger)) { error in
            if let error { print(error.localizedDescription) }
        }
    }

    func completeDailyWalk() {
        let today = Calendar.current.startOfDay(for: Date())
        let lastDate = Date(timeIntervalSince1970: lastWalkDate)
        if Calendar.current.isDate(today, inSameDayAs: lastDate) { return }
        if let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today), Calendar.current.isDate(lastDate, inSameDayAs: yesterday) {
            streak += 1
        } else {
            streak = 0
        }
        lastWalkDate = today.timeIntervalSince1970
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(colors: [NaturePalette.d, NaturePalette.e, NaturePalette.c.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        header
                        treeCard
                        actionGrid
                        Button {
                            infoSheet = true
                        } label: {
                            Label("How it works", systemImage: "questionmark.circle")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(NaturePalette.a)
                                .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
            }
            .navigationBarHidden(true)
        }
        .tint(NaturePalette.b)
        .sheet(isPresented: $shouldPresentScreenTimeSheet) { screenTimeSheet }
        .sheet(isPresented: $shouldPresentSleepSheet) { sleepSheet }
        .sheet(isPresented: $shouldPresentSheet1, onDismiss: {
            if presentWalkQuestionsAfterIntro {
                presentWalkQuestionsAfterIntro = false
                shouldPresentSheet2 = true
            }
        }) { walkIntroSheet }
        .sheet(isPresented: $shouldPresentSheet2) { walkQuestionsSheet }
        .sheet(isPresented: $shouldPresentSheet3) { walkCompleteSheet }
        .sheet(isPresented: $infoSheet) { infoSheetView }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Tree")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .foregroundStyle(NaturePalette.a)
            }
            Spacer()
            VStack(spacing: 2) {
                Image(systemName: "drop.fill")
                    .foregroundStyle(Color(red: 0.18, green: 0.57, blue: 0.72))
                Text("\(water)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(NaturePalette.a)
            }
            .frame(width: 58, height: 58)
            .background(.white.opacity(0.8), in: Circle())
        }
    }

    private var treeCard: some View {
        VStack(spacing: 12) {
            Text(treeMessage)
                .font(.headline)
                .foregroundStyle(NaturePalette.a)
                .multilineTextAlignment(.center)
            treeImage
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 300, minHeight: 300, maxHeight: 350)
            Text("Keep collecting water to grow your tree")
                .font(.caption)
                .foregroundStyle(NaturePalette.a.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .natureCard()
    }

    private var actionGrid: some View {
        VStack(spacing: 12) {
            Text("Tend to your day")
                .font(.title3.weight(.bold))
                .foregroundStyle(NaturePalette.a)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 12) {
                homeAction(title: "Screen time", subtitle: "Set an intention", icon: "iphone", color: .orange) { shouldPresentScreenTimeSheet = true }
                homeAction(title: "Sleep", subtitle: "Log your rest", icon: "moon.stars.fill", color: NaturePalette.b) { shouldPresentSleepSheet = true }
            }
            Button {
                savedDate = Date.now.addingTimeInterval(1296000)
                shouldPresentSheet1 = true
            } label: {
                HStack {
                    Image(systemName: "figure.walk")
                        .font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start a mindful walk").font(.headline)
                        Text("Notice the world around you").font(.caption).opacity(0.82)
                    }
                    Spacer()
                    Image(systemName: "arrow.right").fontWeight(.semibold)
                }
                .foregroundStyle(.white)
                .padding(18)
                .background(NaturePalette.b, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func homeAction(title: String, subtitle: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(title).font(.headline).foregroundStyle(NaturePalette.a)
                Text(subtitle).font(.caption).foregroundStyle(NaturePalette.a.opacity(0.62))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .natureCard()
        }
        .buttonStyle(.plain)
    }
    //Screen Time
    
    

    private var screenTimeSheet: some View {
        NavigationStack {
            Form {
                Section("Your screen-time goal") {
                    Text("Choose an goal that feels realistic today.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Picker("Hours", selection: $selectedHours) { ForEach(0...4, id: \.self) { Text("\($0) h") } }
                        Picker("Minutes", selection: $selectedMinutes) { ForEach([0, 15, 30, 45], id: \.self) { Text("\($0) min") } }
                    }
                }
                Section("Did you reach your goal?") {
                    Button("Yes") { showAlert = true; water += 25 }
                        .foregroundStyle(NaturePalette.b)
                        .alert("Good job! You have \(water) now.", isPresented: $showAlert) {
                            Button("Close") { showAlert = false; shouldPresentScreenTimeSheet = false }
                        }
                    Button("No") { showAlert = true }
                        .foregroundStyle(.red)
                        .alert("Try again tomorrow! You can do it!", isPresented: $showAlert) {
                            Button("Close") { showAlert = false; shouldPresentScreenTimeSheet = false }
                        }
                }
            }
            .scrollContentBackground(.hidden)
            .background(NaturePalette.d)
            .navigationTitle("Screen time")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { shouldPresentScreenTimeSheet = false } } }
        }
    }
//sleep sheet
    
    
    private var sleepSheet: some View {
        NavigationStack {
            Form {
                Section("Rest routine") {
                    Button("Enable notifications") {
                        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { success, error in
                            if success { print("Done!") } else if let error { print(error.localizedDescription) }
                        }
                    }
                    Text("From when to when did you sleep?").foregroundStyle(.secondary)
                    DatePicker("Bedtime", selection: $bedtime, displayedComponents: .hourAndMinute)
                    DatePicker("Wake up time", selection: $wakeTime, displayedComponents: .hourAndMinute)
                }
                Section("Tonight's rest") {
                    HStack {
                        Text("Sleep duration")
                        Spacer()
                        Text(String(format: "%.1f hours", sleepHours))
                            .font(.headline)
                            .foregroundStyle(NaturePalette.a)
                    }
                }
                Section {
                    Button("Collect rewards") { water += Int(sleepHours); water += Int(sleepHours); showAlert = true }
                        .foregroundStyle(NaturePalette.b)
                        .alert("You have \(water) now! Make sure to log your sleep again tomorrow!", isPresented: $showAlert) {
                            Button("Close") { showAlert = false; shouldPresentSleepSheet = false }
                        }
                }
            }
            .scrollContentBackground(.hidden)
            .background(NaturePalette.d)
            .navigationTitle("Sleep tracker")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { shouldPresentSleepSheet = false } } }
        }
    }
    //Walk sheet
    
    

    private var walkIntroSheet: some View {
        VStack(spacing: 24) {
            Image(systemName: "leaf.circle.fill").font(.system(size: 54)).foregroundStyle(NaturePalette.b)
            Text("Take a gentle walk").font(.system(.title, design: .rounded).weight(.bold)).foregroundStyle(NaturePalette.a)
            Text("Keep your phone away for a moment. Notice the little details around you.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            VStack(spacing: 10) {
                InfoRow(icon: "tree.fill", color: NaturePalette.b, text: "The trees")
                InfoRow(icon: "leaf.fill", color: NaturePalette.b, text: "The grass")
                InfoRow(icon: "water.waves", color: .blue, text: "The water")
                InfoRow(icon: "heart.fill", color: .red, text: "How you feel")
                InfoRow(icon: "soccerball", color: NaturePalette.f, text: "Activities going on")
                InfoRow(icon: "car.fill", color: .cyan, text: "The cars")
            }
            if showButton {
                Button("I'm ready to reflect") { showAlert = true }
                    .buttonStyle(.borderedProminent)
                    .tint(NaturePalette.b)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(24)
        .background(NaturePalette.d.ignoresSafeArea())
        .task {
            try? await Task.sleep(nanoseconds: 500)
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { showButton = true }
        }
        .alert("Are you sure you want to continue to the next page?", isPresented: $showAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Continue") {
                showAlert = false
                completeDailyWalk()
                presentWalkQuestionsAfterIntro = true
                shouldPresentSheet1 = false
            }
        }
    }

    private var walkQuestionsSheet: some View {
        NavigationStack {
            Form {
                Section("Was the walk enjoyable?") { TextField("Optional", text: $question1) }
                Section("What were the surroundings like?") { TextField("Optional", text: $question2) }
                Section("What was the most interesting thing on your walk?") { TextField("Optional", text: $question3) }
                Section("How do you feel after the walk?") { TextField("Optional", text: $question4) }
                Section {
                    Button("Collect rewards") {
                        Task {
                            await healthStore.requestAuthorization()
                            do { try await healthStore.calculateSteps() } catch { print(error) }
                            shouldPresentSheet3 = true
                            if !question1.isEmpty { water += 5 }
                            if !question2.isEmpty { water += 10 }
                            if !question3.isEmpty { water += 10 }
                            if !question4.isEmpty { water += 5 }
                          
                            water += healthStore.steps / 100
                            question1 = ""; question2 = ""; question3 = ""; question4 = ""
                        }
                    }
                    .foregroundStyle(NaturePalette.b)
                }
            }
            .scrollContentBackground(.hidden)
            .background(NaturePalette.d)
            .navigationTitle("Your walk")
        }
    }

    private var walkCompleteSheet: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 64)).foregroundStyle(NaturePalette.b)
            Text("Good job!").font(.system(.largeTitle, design: .rounded).weight(.bold)).foregroundStyle(NaturePalette.a)
            Text("\(healthStore.steps) steps").font(.title3).foregroundStyle(NaturePalette.a.opacity(0.72))
            Text("Total water: \(water) 💧").font(.title2.weight(.bold)).foregroundStyle(NaturePalette.a)
            Spacer()
            Button("Back to home") {
                if streak == 7 { water += 50; streak = 0; showAlert = true }
                else { shouldPresentSheet1 = false; shouldPresentSheet2 = false; shouldPresentSheet3 = false; healthStore.steps = 0 }
            }
            .buttonStyle(.borderedProminent).tint(NaturePalette.b)
//            .alert("7 Day Streak!", isPresented: $showAlert) {
//                Button("OK") { shouldPresentSheet1 = false; shouldPresentSheet2 = false; shouldPresentSheet3 = false; healthStore.steps = 0 }
//            } message: {
//                Text("You achieved a 7 day streak! An extra 20 💧 has been added.")
//            }
        }
        .padding(28)
        .background(NaturePalette.d.ignoresSafeArea())
        .task {
            await healthStore.requestAuthorization()
            do { try await healthStore.calculateSteps() } catch { print(error) }
        }
    }
    //infosheet

    private var infoSheetView: some View {
        NavigationStack {
            List {
                Section("Grow your grove") {
                    Label("Set and meet a screen-time goal to earn water.", systemImage: "iphone")
                    Label("Log your rest to earn water for your tree.", systemImage: "moon.stars.fill")
                    Label("Take a walk and reflect on it for additional water.", systemImage: "figure.walk")
                    Label("The water you collect grows your tree.", systemImage: "tree.fill")
                }
            }
            .scrollContentBackground(.hidden)
            .background(NaturePalette.d)
            .navigationTitle("How it works")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { infoSheet = false } } }
        }
    }

    struct InfoRow: View {
        let icon: String
        let color: Color
        let text: String

        var body: some View {
            HStack(spacing: 14) {
                Image(systemName: icon).foregroundStyle(color).frame(width: 24)
                Text(text).foregroundStyle(NaturePalette.a)
                Spacer()
            }
            .padding(14)
            .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

#Preview { ContentView() }
