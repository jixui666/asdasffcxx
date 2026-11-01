//
//  Signup.swift
//  LoginKit
//
//  Created by zues on 04/08/23.
//

import SwiftUI

struct SignUp: View {
    
    @Binding var isLoggedIn: Bool
    @Binding var showSignup: Bool
    
    
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    /// View Properties
    @State private var emailID: String = ""
    @State private var fullName: String = ""
    @State private var password: String = ""
    /// Optional, Present If you want to ask OTP for Signup
    @State private var askOTP: Bool = false
    @State private var otpText: String = ""

    private var passwordMeetsRequirements: Bool {
        password.unicodeScalars.count >= 8
            && password.range(of: "[A-Z]", options: .regularExpression) != nil
            && password.range(of: "[a-z]", options: .regularExpression) != nil
            && password.range(of: "[0-9]", options: .regularExpression) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15, content: {
            
          
//            HStack{
//                Spacer()
//                Image("applogo").resizable().frame(width: 100, height: 100).cornerRadius(20)
//                Spacer()
//            }
            
            
            Text("注册")
                .font(.largeTitle)
                //.fontWeight(.heavy)
                .padding(.top, 25)
            
            Text("请按注册按钮继续")
                .font(.callout)
                //.fontWeight(.semibold)
                .foregroundStyle(.gray)
                .padding(.top, -5)
            
            VStack(spacing: 25) {
                /// Custom Text Fields
                CustomTF(sfIcon: "at", hint: "Email", value: $emailID)
                
                VStack(alignment: .leading, spacing: 8) {
                    CustomTF(sfIcon: "lock", hint: "密码", isPassword: true, value: $password)
                    Text("密码至少 8 位，且须包含\n大写字母、小写字母和数字")
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 5)
                
                CustomTF(sfIcon: "person", hint: "邀请人（可不填）", value: $fullName)
                    .padding(.top, 5)
                
                
                Text("通过注册，你同意我们的[条款和条件](https://minipanda.soccertt.com/teams.html)和[隐私政策](https://minipanda.soccertt.com/privacy.html)")
                    .font(.caption)
                    .tint(.white)
                    .foregroundStyle(.gray)
                    .frame(height: 50)
                
                
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
                
                
                /// SignUp Button
                GradientButton(title: "注册", icon: "arrow.right") {
                    /// YOUR CODE
                    //askOTP.toggle()
                    Task{
                        await logupUser()
                    }
                }
                .hSpacing(.trailing)
                /// Disabling Until the Data is Entered  || fullName.isEmpty
                .disableWithOpacity(emailID.isEmpty || password.isEmpty || isLoading)
            }
            .padding(.top, 20)
            
            Spacer(minLength: 0)
            
            HStack(spacing: 6) {
                Text("已经有账号?")
                    .foregroundStyle(.gray)
                
                Button("登录") {
                    showSignup = false
                }
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
                   // .presentationDetents([.height(350)])
            }
        })
    }
    
    
    // MARK: - Networking Logic

    func logupUser() async {
        guard passwordMeetsRequirements else {
            errorMessage = "密码至少 8 位，且须包含大写字母、小写字母和数字"
            return
        }

        isLoading = true
        errorMessage = nil

        guard let loginUrl = URL(string: "\(UserManager.shared.baseURL())passport/auth/register"),
              loginUrl.scheme == "https", loginUrl.host != nil else {
            errorMessage = "服务器配置未就绪，请稍后重试"
            isLoading = false
            return
        }
        var request = URLRequest(url: loginUrl, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let loginData = ["email": emailID, "password": password, "captchaData": "","email_code":"","invite_code":fullName]
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
                    self.errorMessage = "注册失败: \(error.localizedDescription)"
                    return
                }
                
                guard let data = data else {
                    self.errorMessage = "注册失败：数据返回空"
                    return
                }

                let httpStatus = (response as? HTTPURLResponse)?.statusCode
                guard let httpStatus = httpStatus, (200..<300).contains(httpStatus) else {
                    self.errorMessage = AuthResponseSupport.message(from: data)
                        ?? "注册失败（HTTP \(httpStatus ?? 0)）"
                    return
                }
                if AuthResponseSupport.indicatesFailure(data) {
                    self.errorMessage = AuthResponseSupport.message(from: data) ?? "注册失败，请检查注册信息"
                    return
                }

                guard let jsonResponse = try? JSONDecoder().decode(LoginResponseSuccess.self, from: data) else {
                    self.errorMessage = AuthResponseSupport.message(from: data)
                        ?? "注册失败：服务器返回的数据无法识别"
                    return
                }

                if let authData = jsonResponse.data?.authData,
                   !authData.isEmpty {
                    UserManager.shared.updateLoginStatus(true)
                    UserManager.shared.storeAutoData(data: authData)
                    self.isLoggedIn = true
                } else {
                    self.errorMessage = AuthResponseSupport.message(from: data)
                        ?? "注册失败：服务器响应中缺少认证信息"
                }
                

            }
        
        }

        task.resume()
    }
}


/***
 {
     "status": "success",
     "message": "\u64cd\u4f5c\u6210\u529f",
     "data": {
         "token": "56ffc6d0465212eca2856aa25dc1644e",
         "is_admin": null,
         "auth_data": "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpZCI6MTU0MDMsInNlc3Npb24iOiJiYzk3N2RhOTczN2RjZWVlM2FiNDc2NzAzMjBjOTI2OCJ9.WUPCzTlgsOMGM-DrsSMRrfBqgAB8GEysDyAofq6TgVo"
     },
     "error": null
 }
 
 */
 
