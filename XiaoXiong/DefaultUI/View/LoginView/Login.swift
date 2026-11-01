//
//  Login.swift
//  LoginKit
//
//  Created by zues on 04/08/23.
//

import SwiftUI
 
import Crisp

struct LoginResponseSuccess: Codable {
    let data: LoginResponseSuccessClass?
    let message: String?
    let status: String?
}

// MARK: - DataClass
struct LoginResponseSuccessClass: Codable {
    let token: String?
    let authData: String?

    enum CodingKeys: String, CodingKey {
        case token
        case authData = "auth_data"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        token = try? container.decode(String.self, forKey: .token)
        authData = try? container.decode(String.self, forKey: .authData)
    }
}

enum AuthResponseSupport {
    static func message(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let response = object as? [String: Any] else { return nil }

        for key in ["message", "msg", "error", "errors"] {
            if let text = readableText(response[key]), !text.isEmpty {
                return text
            }
        }
        return nil
    }

    static func indicatesFailure(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let response = object as? [String: Any] else { return false }

        if let status = response["status"] as? String,
           ["fail", "failed", "error"].contains(status.lowercased()) {
            return true
        }
        if let status = response["status"] as? Int, status != 1 && status != 200 {
            return true
        }
        if let success = response["success"] as? Bool, !success {
            return true
        }
        return ["error", "errors"].contains { key in
            guard let value = response[key], !(value is NSNull) else { return false }
            return readableText(value) != nil
        }
    }

    private static func readableText(_ value: Any?) -> String? {
        guard let value = value, !(value is NSNull) else { return nil }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let values = value as? [Any] {
            let messages = values.compactMap(readableText)
            return messages.isEmpty ? nil : messages.joined(separator: "；")
        }
        if let values = value as? [String: Any] {
            for key in ["message", "msg", "error", "errors"] {
                if let text = readableText(values[key]) { return text }
            }
            let messages = values.keys.sorted().compactMap { readableText(values[$0]) }
            return messages.isEmpty ? nil : messages.joined(separator: "；")
        }
        return nil
    }
}



struct Login: View {
    
    @Binding var isLoggedIn: Bool
    
    @Binding var showSignup: Bool
    let isConfigurationReady: Bool
    let isLoadingConfiguration: Bool
    let configurationError: String?
    let onEnsureConfiguration: () async -> Bool
    
    /// View Properties
    @State private var emailID: String = ""
    
    @State private var password: String = ""
    @State private var showForgotPasswordView: Bool = false
    /// Reset Password View (with New Password and Confimration Password View)
    @State private var showResetView: Bool = false
    /// Optional, Present If you want to ask OTP for login
    @State private var askOTP: Bool = false
    @State private var otpText: String = ""
    
    @State private var showKefuView: Bool = false

    
    @State private var userInfo: UserInfo? = nil
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var alert: Alert?
    @State private var okMessage: String?
    
    @State private var isresetpwdLoading = false
    @State private var  resetpwdErrorMessage = ""
    
    @AppStorage("isFirstOpen") private var isFirstOpen: Bool?
    @State private var isWaitingForConfiguration = false
    @State private var showOnboardingConfigurationError = false
    
    @State var onboardingItems: [OnboardingItem] = [
        .init(title: "最稳定的加速器",
              subTitle: "順暢瀏覽社交媒體，同時支持Netflix及Youtube等流媒體內容平台，4K清晰度不卡頓。",
              lottieView: .init(name: "12c853b3",bundle: .main)),
        .init(title: "永不跑路的VPN加速器",
              subTitle: "一鍵訪問匿名互聯網，告別繁瑣的配置，跨平臺設備支持，隨時隨地連接網絡。",
              lottieView: .init(name: "2c630b55",bundle: .main)),
        .init(title: "加密访问，全球畅连",
              subTitle: "隱藏您的IP地址。互聯網流量通過TLS加密保護免受任何黑客探測、監控和攻擊。",
              lottieView: .init(name: "5a519db7",bundle: .main))
    ]
    // MARK: Current Slide Index
    @State var currentIndex: Int = 0
    
    var onBoardView: some View {
        
        GeometryReader{
            let size = $0.size
            VStack(spacing: 40, content: {
                Spacer().frame(height: 10)
            
            HStack(spacing: 0){
                ForEach($onboardingItems) { $item in
                    let isLastSlide = (currentIndex == onboardingItems.count - 1)
                    VStack{
                        // MARK: Top Nav Bar
                        HStack{
                            Button(action: {
                                if currentIndex > 0{
                                    currentIndex -= 1
                                    playAnimation()
                                }
                            }, label: {
                                Image(systemName: "arrow.backward")
                            }).tint(Color("Main"))
                            .opacity(currentIndex > 0 ? 1 : 0)
                            
                            Spacer(minLength: 0)
                            
//                            Button("跳过"){
//                                currentIndex = onboardingItems.count - 1
//                                playAnimation()
//                            }
//                            .opacity(isLastSlide ? 0 : 1)
                        }
                        .animation(.easeInOut, value: currentIndex)
                        .tint(Color("Main"))
                        //.fontWeight(.bold)
                        
                        // MARK: Movable Slides
                        VStack(spacing: 15){
                            let offset = -CGFloat(currentIndex) * size.width
                            // MARK: Resizable Lottie View
                            ResizableLottieView(onboardingItem: $item)
                                .frame(height: size.width*0.8)
                                .onAppear {
                                    // MARK: Intially Playing First Slide Animation
                                    if currentIndex == indexOf(item){
                                        item.lottieView.play(toProgress: 0.7)
                                    }
                                }
                                .offset(x: offset)
                                .animation(.easeInOut(duration: 0.5), value: currentIndex)
                            
                            Text(item.title)
                                .font(.title.bold())
                                .offset(x: offset)
                                .animation(.easeInOut(duration: 0.5).delay(0.1), value: currentIndex)
                            
                            Text(item.subTitle)
                                .font(.system(size: 14))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal,15)
                                .foregroundColor(.gray)
                                .offset(x: offset)
                                .animation(.easeInOut(duration: 0.5).delay(0.2), value: currentIndex)
                        }
                        
                        Spacer(minLength: 0)
                        
                        // MARK: Next / Login Button
                        VStack(spacing: 15){
                            Button(isLastSlide ? (showOnboardingConfigurationError && !isConfigurationReady ? "重试连接" : "登录") : "下一步") {
                                if isLastSlide {
                                    guard !isWaitingForConfiguration else { return }
                                    isWaitingForConfiguration = true
                                    showOnboardingConfigurationError = false
                                    Task {
                                        let isReady = await onEnsureConfiguration()
                                        isWaitingForConfiguration = false
                                        if isReady {
                                            withAnimation { isFirstOpen = false }
                                        } else {
                                            showOnboardingConfigurationError = true
                                        }
                                    }
                                } else {
                                    advanceSlide()
                                    if !isConfigurationReady {
                                        Task { _ = await onEnsureConfiguration() }
                                    }
                                }
                            }
//                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.vertical,isLastSlide ? 13 : 12)
                                .frame(maxWidth: .infinity)
                                .background {
                                    Capsule()
                                        .fill(Color("Main2"))
                                }
                                .padding(.horizontal,isLastSlide ? 50 : 100)
                                .disabled(isWaitingForConfiguration)

                            if isLastSlide && isWaitingForConfiguration {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("正在连接服务器…")
                                }
                                .font(.caption)
                            } else if isLastSlide && showOnboardingConfigurationError && !isConfigurationReady,
                                      let configurationError {
                                Text(configurationError)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                            }
                                
                            
                            if currentIndex == onboardingItems.count - 1{
                                
                                HStack{
//                                    Button("Terms of Service"){}
                                        
//                                    Button("Privacy Policy"){}
                                }
                                .font(.caption2)
                                //.underline(true, color: .primary)
                                .offset(y: 5)
                            }
                        }
                    }
                    .animation(.easeInOut, value: isLastSlide)
                    .padding(15)
                    .frame(width: size.width, height: size.height)
                }
            }
            .frame(width: size.width * CGFloat(onboardingItems.count),alignment: .leading)
            }).ignoresSafeArea(.all)
             
//            if !#available(iOS 15.0, *) {
//
//            }
        }
    }

    private func advanceSlide() {
        guard currentIndex < onboardingItems.count - 1 else { return }
        let currentProgress = onboardingItems[currentIndex].lottieView.currentProgress
        onboardingItems[currentIndex].lottieView.currentProgress = (currentProgress == 0 ? 0.7 : currentProgress)
        currentIndex += 1
        playAnimation()
    }
    
    func playAnimation(){
        onboardingItems[currentIndex].lottieView.currentProgress = 0
        onboardingItems[currentIndex].lottieView.play(toProgress: 0.7)
    }
    
    // MARK: Retreving Index of the Item in the Array
    func indexOf(_ item: OnboardingItem)->Int{
        if let index = onboardingItems.firstIndex(of: item){
            return index
        }
        return 0
    }
    
    var body: some View {
        if isFirstOpen ?? true {
            onBoardView
        }else{
            loginView
        }
        
    }
    
    var loginView: some View {
        VStack(alignment: .leading, spacing: 15, content: {
            Spacer(minLength: 0)
            
//            HStack{
//                Spacer()
//                Image("applogo").resizable().frame(width: 100, height: 100).cornerRadius(20)
//                Spacer()
//            }
            
            Text("登录")
                .font(.largeTitle)
                //.fontWeight(.heavy)
            
            Text("请按登录按钮继续")
                .font(.callout)
                //.fontWeight(.semibold)
                .foregroundStyle(.gray)
                .padding(.top, -5)
            
            VStack(spacing: 25) {
                /// Custom Text Fields
                CustomTF(sfIcon: "at", hint: "Email", value: $emailID)
                
                CustomTF(sfIcon: "lock", hint: "密码", isPassword: true, value: $password)
                    .padding(.top, 5)
                
                
                HStack(content: {
                    
                    Button("忘记密码?") {
                        showForgotPasswordView.toggle()
                    }
                    .font(.callout)
                    //.fontWeight(.heavy)
                    .tint(.white)
                    .disabled(!isConfigurationReady)
                                        
                    Button {
                        showKefuView.toggle()
                    } label: {
                   
                        Text("联系客服") .font(.callout)
                        Image(systemName: "person.crop.circle.badge.questionmark")
                    }.tint(.white)
                })
                .hSpacing(.trailing)
                
                
                
                /// Login Button
                ///
                if isLoading {
                      ProgressView()
                  }
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .bold()
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center) // 确保多行文本居中
                        .padding()
                }
                
                if let okmsg = okMessage {
                    Text(okmsg)
                        .bold()
                        .foregroundColor(Color("Main"))
                        .multilineTextAlignment(.center) // 确保多行文本居中
                        .padding()
                }

                if !isConfigurationReady {
                    if isLoadingConfiguration || configurationError == nil {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("正在连接服务器…")
                        }
                        .font(.callout)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(configurationError ?? "服务器配置未就绪")
                                .foregroundColor(.red)
                            Button("重试连接") {
                                Task { _ = await onEnsureConfiguration() }
                            }
                        }
                        .font(.callout)
                    }
                }

                if let userInfo = userInfo {
                    Text("Logged in as: \(userInfo.data.email)")
//                    AsyncImage(url: URL(string: userInfo.data.avatar_url))
//                        .frame(width: 64, height: 64)
//                        .clipShape(Circle())
                }
 
                GradientButton(title: "登录", icon: "arrow.right") {
                    /// YOUR CODE
                    //askOTP.toggle()
                    Task{
                        await loginUser()
                    }
                }
                .hSpacing(.trailing)
                /// Disabling Until the Data is Entered
                .disableWithOpacity(emailID.isEmpty || password.isEmpty || isLoading || !isConfigurationReady)
            }
            .padding(.top, 20)
          
            
            Spacer(minLength: 0)
            
            HStack(spacing: 6) {
                Text("没有账号？")
                    .foregroundStyle(.gray)
                
                Button("注册") {
                    showSignup.toggle()
                }
                .disabled(!isConfigurationReady)
                //.fontWeight(.bold)
                .tint(.white)
            }
            .font(.callout)
            .hSpacing()
        })
        .padding(.vertical, 15)
        .padding(.horizontal, 25)
        .background {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { hideKeyboard() }
        }
        //.toolbar(.hidden, for: .navigationBar)
        /// Asking Email ID For Sending Reset Link
        .sheet(isPresented: $showForgotPasswordView, content: {
            if #available(iOS 16.4, *) {
                /// Since I wanted a Custom Sheet Corner Radius
                ForgotPassword(showResetView: $showResetView, emailID: $emailID, otpText: $otpText)
                    .presentationDetents([.height(300)])
                    .presentationCornerRadius(30)
            } else {
                ForgotPassword(showResetView: $showResetView, emailID: $emailID, otpText: $otpText)
                  //  .presentationDetents([.height(300)])
            }
        })
        .fullScreenCover(isPresented: $showKefuView, content: {
            SupportView()
        })
        /// Resetting New Password
        .sheet(isPresented: $showResetView, content: {
            if #available(iOS 16.4, *) {
                /// Since I wanted a Custom Sheet Corner Radius
                
                PasswordResetView(isresetpwdLoading: $isresetpwdLoading, resetpwdErrorMessage: $resetpwdErrorMessage) { password in
                    print(otpText + "  " + password)
                    
                    Task{
                        await resetpwd(password:password)
                    }
                }
                    .presentationDetents([.height(350)])
                    .presentationCornerRadius(30)
            } else {
                PasswordResetView(isresetpwdLoading: $isresetpwdLoading, resetpwdErrorMessage: $resetpwdErrorMessage){password in
                    print(otpText + "  " + password)
                    
                    Task{
                        await resetpwd(password:password)
                    }
                }
                   // .presentationDetents([.height(350)])
            }
        })
        .alertBinding($alert)
        /// OTP Prompt
        .sheet(isPresented: $askOTP, onDismiss: {
            /// YOUR CODE
            /// Reset OTP if You Want
            // otpText = ""
        }, content: {
            if #available(iOS 16.4, *) {
                /// Since I wanted a Custom Sheet Corner Radius
                OTPView(otpText: $otpText)
                    .presentationDetents([.height(350)])
                    .presentationCornerRadius(30)
            } else {
                OTPView(otpText: $otpText)
                    //.presentationDetents([.height(350)])
            }
        })
    }
    
    func resetpwd(password:String)  async {
        isresetpwdLoading = true
        guard let loginUrl = URL(string: "\(UserManager.shared.baseURL())passport/auth/forget?email=\(emailID)&password=\(password)&email_code=\(otpText)"),
              loginUrl.scheme == "https", loginUrl.host != nil else {
            resetpwdErrorMessage = "服务器配置未就绪，请稍后重试"
            isresetpwdLoading = false
            return
        }
        var request = URLRequest(url: loginUrl, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        
        print(loginUrl)
        let loginData = ["email": emailID, "password": password, "email_code": otpText]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: loginData) else {
            self.resetpwdErrorMessage = "请求格式错误"
            self.isresetpwdLoading = false
            return
        }
        
        request.httpBody = httpBody
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isresetpwdLoading = false
                if let error = error {
                    resetpwdErrorMessage = ( "密码重置失败: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    resetpwdErrorMessage = ("密码重置失败: 数据为空")
                    return
                }

                let httpStatus = (response as? HTTPURLResponse)?.statusCode
                guard let httpStatus = httpStatus, (200..<300).contains(httpStatus) else {
                    resetpwdErrorMessage = AuthResponseSupport.message(from: data)
                        ?? "密码重置失败（HTTP \(httpStatus ?? 0)）"
                    return
                }
                
                struct resetpwdResponseSuccess: Codable {
                    let message: String?
                    let status: String?
                }
                 
                // Parse the login response and get the authorization token
                if let jsonResponse = try? JSONDecoder().decode(resetpwdResponseSuccess.self, from: data){
                    dump(jsonResponse)
                    
                    if    let status = jsonResponse.status , status == "success" {
                          
                        withAnimation {
                            showResetView = false
                                                       
                        }
                        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1) {
                            alert = Alert(okMessage: "密码重置成功!")
                        }
                    }else{
                        resetpwdErrorMessage = AuthResponseSupport.message(from: data)
                            ?? "密码重置失败: 未知错误"
                    }
                }else{
                    resetpwdErrorMessage = AuthResponseSupport.message(from: data)
                        ?? "密码重置失败：服务器返回的数据无法识别"
                }
            }
        
        }

        task.resume()
        
    }
    
    // MARK: - Networking Logic
 
    func loginUser()  async {
        isLoading = true
        errorMessage = nil
        hideKeyboard()
        guard let loginUrl = URL(string: "\(UserManager.shared.baseURL())passport/auth/login"),
              loginUrl.scheme == "https", loginUrl.host != nil else {
            errorMessage = "服务器配置未就绪，请稍后重试"
            isLoading = false
            return
        }
        var request = URLRequest(url: loginUrl, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let loginData = ["email": emailID, "password": password, "captchaData": ""]
        guard let httpBody = try? JSONSerialization.data(withJSONObject: loginData) else {
            self.errorMessage = "Invalid login data"
            self.isLoading = false
            return
        }
        
        request.httpBody = httpBody

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = "登录失败: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self.errorMessage = "登录失败: 数据为空"
                    return
                }

                let httpStatus = (response as? HTTPURLResponse)?.statusCode
                guard let httpStatus = httpStatus, (200..<300).contains(httpStatus) else {
                    self.errorMessage = AuthResponseSupport.message(from: data)
                        ?? "登录失败（HTTP \(httpStatus ?? 0)）"
                    return
                }
                if AuthResponseSupport.indicatesFailure(data) {
                    self.errorMessage = AuthResponseSupport.message(from: data) ?? "登录失败，请检查账号信息"
                    return
                }

                guard let jsonResponse = try? JSONDecoder().decode(LoginResponseSuccess.self, from: data) else {
                    self.errorMessage = AuthResponseSupport.message(from: data)
                        ?? "登录失败：服务器返回的数据无法识别"
                    return
                }

                if let authData = jsonResponse.data?.authData,
                   !authData.isEmpty {
                    UserManager.shared.updateLoginStatus(true)
                    UserManager.shared.storeAutoData(data: authData)
                    self.okMessage = "登录成功,正在跳转..."
                    self.isLoading = true
                    UserManager.shared.storeUserInfo(email: emailID, avator: "")

                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1) {
                        self.isLoggedIn = true
                    }
                } else {
                    self.errorMessage = AuthResponseSupport.message(from: data)
                        ?? "登录失败：服务器响应中缺少认证信息"
                }
                //{"data":{"token":"880e8785746c0bf72b2e01a882a678e7","is_admin":1,"auth_data":"eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpZCI6Miwic2Vzc2lvbiI6Ijc4MzE1Yjc5YmNlNTliYWIzOTg5MTIzMTFhNDkwN2NiIn0.00fdwJ85bOSycfnkOPmhF7pSR1VV9WczBEeE9aXncQQ"}}

            }
        
        }

        task.resume()
    }
    
    func fetchUserInfo(token: String) async {
        let userInfoUrl = URL(string: "\(UserManager.shared.baseURL())user/info")!
        var request = URLRequest(url: userInfoUrl)
        request.httpMethod = "GET"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("\(token)", forHTTPHeaderField: "Authorization")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = "Failed to get user info: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self.errorMessage = "No user data received"
                    return
                }
                
               
                // Parse the user info response
                if let userInfo = try? JSONDecoder().decode(UserInfo.self, from: data) {
                    self.userInfo = userInfo
                    // Save user info to local storage
                    
                    
                    UserManager.shared.saveUserInfoToLocal(userInfo: userInfo)
                    UserManager.shared.storeUserInfo(email: userInfo.data.email, avator:  userInfo.data.avatar_url)
                    
                    
                    // 读取登录状态和用户信息
                    let isLoggedIn = UserManager.shared.isUserLoggedIn()
                    let userInfo = UserManager.shared.getUserInfo()
                    let autoData = UserManager.shared.getAutoData()

                    print("Logged in: \(isLoggedIn)")
                    print("Email: \(userInfo.email), avator: \(userInfo.avator)")
                    print("Auto Data: \(autoData)")
                    self.isLoggedIn = true
                    
                }
            }
        }

        task.resume()
    }

    // Save user info to local storage (UserDefaults)
    
    /**
     {"data":{"email":"ceshi1@qq.com","transfer_enable":119185342464,"device_limit":null,"last_login_at":1725893596,"created_at":1725893596,"banned":0,"remind_expire":1,"remind_traffic":1,"expired_at":null,"balance":0,"commission_balance":0,"plan_id":1,"discount":null,"commission_rate":null,"telegram_id":null,"uuid":"0b0d55e3-9f6f-4ee0-9a73-2901655cfaf2","avatar_url":"https:\/\/cravatar.cn\/avatar\/845735bc7a6186ae5bad56e7cb87d88b?s=64&d=identicon"}}
     */
    
 
    
}
 
