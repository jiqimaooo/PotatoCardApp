//
//  PIckBleManager.h
//  PIckBleManager
//
//  Created by picksmart on 2024/12/6.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef void (^BleEventSink)(id _Nullable event);

@protocol PickBleManagerDelegate <NSObject>

@required

///蓝牙状态通知
/*
 0:Bluetooth is currently powered off./蓝牙当前已关闭
 1:Bluetooth is currently powered on and available to use./蓝牙当前打开，可以使用
 2:The application is not authorized to use the Bluetooth Low Energy role/应用程序无权使用低功耗蓝牙角色。
 3:State unknown, update imminent./状态未知，即将更新
 4:The platform doesn't support the Bluetooth Low Energy Central/Client role/平台不支持低功耗蓝牙中央/客户端角色
 5:The connection with the system service was momentarily lost, update imminent/与系统服务的连接暂时丢失，即将更新
 */
- (void)didBluetoothStatusNotification:(NSInteger)state;
/*
 返回当前蓝牙搜索到的设备
 */
- (void)bluetoothSearchDevice:(NSDictionary*_Nonnull)device;
/*
 返回当前蓝牙设备传输数据的进度和状态
 */
-(void)updateProgress:(NSDictionary*_Nonnull)device;

@end


@interface PickBleManager : NSObject
//实现代理属性
@property (assign,nonatomic) id<PickBleManagerDelegate> _Nonnull delegate;
+ (instancetype _Nonnull )sharedManager;
///蓝牙手动开始工作
-(void)startWork;
/// 开始扫描
-(void)startScan;
/// 停止扫描
-(void)stopScan;
///外设搜索成功后传输图片
-(void)updateImageWithDevice:(NSDictionary *_Nonnull)device image:(UIImage *_Nonnull)image;

@end
