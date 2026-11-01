import Library
import SwiftUI

@MainActor
public struct InstallProfileButton: View {
    
    private let callback: (Error?) async -> Void
    public init(_ callback: @escaping ((Error?) async -> Void)) {
        self.callback = callback
    }

    public var body: some View {
        parsePowerButton()

       /* FormButton {
            Task {
                await installProfile()
            }
        } label: {
            Label("安装VPN网络扩展", systemImage: "lock.doc.fill")
                .font(.title3)
                .padding(15)
                .foregroundColor(.red)
                .background(
                    
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.white.opacity(0.25),lineWidth: 1)
                )
        }
        .alertBinding($alert)*/
    }

     
    
    @ViewBuilder
    func parsePowerButton()->some View{
        
        Button {
            
            Task {
                await installProfile()
            }
        } label: {

            ZStack{
                
                ZStack{
                    //
//                    LottieView(animationFileName: "1d2a0fe5" , loopMode: .loop)
                    LottieView(animationFileName: "8dfa14a6" , loopMode: .loop).scaleEffect(0.2)
                    Text("开启服务").bold().font(.title2).foregroundStyle(Color.white)
                    
                }

            }
            // Max Frame...
            .frame(width: 190,height: 190)

        }.padding()
        

    }
    
    private func installProfile() async {
        
        print("installProfile...")
        #if os(iOS) && targetEnvironment(simulator)
        await callback(NSError(
            domain: "UUVPN.VPNConfiguration",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "iOS 模拟器无法保存 VPN 配置，请在已启用 Network Extension 权限的签名真机版本中测试开启服务。"]
        ))
        return
        #else
        do {
            try await ExtensionProfile.install()
            await callback(nil)
            
            
        } catch {
            print("installProfile: \(error.localizedDescription)")
            await callback(error)
        // alert = Alert(error)
        }
        #endif
        
    }
}
