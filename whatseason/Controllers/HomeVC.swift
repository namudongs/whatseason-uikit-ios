//
//  HomeVC.swift
//  whatseason
//
//  Created by namdghyun on 1/3/24.
//

import CoreLocation
import WeatherKit
import UIKit

class HomeVC: UIViewController {
    // MARK: - 프로퍼티
    var homeView = HomeView()
    let locationManager = CLLocationManager()
    let weatherKitservice = WeatherService()
    
    let currentWService = CurrentWService()
    let hourlyWService = HourlyWService()
    let dailyWService = DailyWService()
    let weeklyWService = WeeklyWService()
    
    var anyW = AnyW()
    let dispatchGroup = DispatchGroup()
    
    // 위치 정보를 불러왔는지 확인
    var hasReceivedLocationUpdate = false
    
    let loadingView = LoadingView()
    // MARK: - 라이프사이클
    override func loadView() {
        view = homeView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        homeView.setUpView()
        
        view.addSubview(loadingView)
        loadingView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        getUserLocation()
    }
    
    // MARK: - 메서드
    /// 유저에게 위치 정보 권한을 요청하고 위치 정보를 불러옵니다.
    func getUserLocation() {
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLHeadingFilterNone
        
        // 날씨 데이터에 대한 권한 설정
        locationManager.requestWhenInUseAuthorization()
        locationManager.delegate = self
        locationManager.startUpdatingLocation()
    }
    
    func getAllWeather(date: Date, x: Int, y: Int, loc: CLLocation, address: String, regId: String, stnId: String, groupRegId: String) {
        let start = CFAbsoluteTimeGetCurrent()
        print("********************************")
        // 기상청 날씨 데이터 요청
        dispatchGroup.enter()
        getKMACurrent(date, x, y)
        
        dispatchGroup.enter()
        getKMAHourly(date, x, y)
        
        dispatchGroup.enter()
        getKMADaily(date, x, y)
        
        dispatchGroup.enter()
        getKMAWeekly(date, regId, stnId, groupRegId)
        
        // Apple 날씨 데이터 요청
        dispatchGroup.enter()
        getWeatherKit(loc)
        
        dispatchGroup.notify(queue: .main) {
            print("비동기 작업 종료")
//            self.printTest(self.anyW)
            
            self.anyW.address = address
            self.updateFromAnyWeather(self.anyW, address)
            self.loadingView.removeFromSuperview()
            self.homeView.homeThirdView.collectionView.reloadData()
            let end = CFAbsoluteTimeGetCurrent() - start
            print("실행 시간: \(end)")
        }
    }
    
    func getKMAWeekly(_ date: Date, _ regId: String, _ stnId: String, _ groupRegId: String, retryCount: Int = 0) {
        Task {
            if let result = await weeklyWService.fetchW(date: date, regId: regId, stnId: stnId, groupRegId: groupRegId) {
                DispatchQueue.main.async {
                    self.anyW.weeklyW = result
                    print("기상청 중기예보를 불러왔습니다.")
                    self.dispatchGroup.leave()
                }
            } else {
                if retryCount < 3 {
                    print("기상청 중기예보를 불러오는데에 실패했습니다. 재시도 중...")
                    getKMAWeekly(date, regId, stnId, groupRegId, retryCount: retryCount + 1)
                } else {
                    print("기상청 중기예보를 불러오는데 최종적으로 실패했습니다.")
                    self.dispatchGroup.leave()
                }
            }
        }
    }
    
    func getKMADaily(_ date: Date, _ nx: Int, _ ny: Int, retryCount: Int = 0) {
        Task {
            if let result = await dailyWService.fetchW(date: date, nx: nx, ny: ny) {
                DispatchQueue.main.async {
                    self.anyW.dailyW = result
                    print("기상청 단기예보를 불러왔습니다.")
                    self.dispatchGroup.leave()
                }
            } else {
                if retryCount < 3 {
                    print("기상청 단기예보를 불러오는데에 실패했습니다. 재시도 중...")
                    getKMADaily(date, nx, ny, retryCount: retryCount + 1)
                } else {
                    print("기상청 단기예보를 불러오는데 최종적으로 실패했습니다.")
                    self.dispatchGroup.leave()
                }
            }
        }
    }
    
    func getKMAHourly(_ date: Date, _ nx: Int, _ ny: Int, retryCount: Int = 0) {
        Task {
            if let result = await hourlyWService.fetchW(date: date, nx: nx, ny: ny) {
                DispatchQueue.main.async {
                    self.anyW.hourlyW = result
                    print("기상청 초단기예보를 불러왔습니다.")
                    
                    self.dispatchGroup.leave()
                }
            } else {
                if retryCount < 3 {
                    print("기상청 초단기예보를 불러오는데에 실패했습니다. 재시도 중...")
                    getKMAHourly(date, nx, ny, retryCount: retryCount + 1)
                } else {
                    print("기상청 초단기예보를 불러오는데 최종적으로 실패했습니다.")
                    self.dispatchGroup.leave()
                }
            }
        }
    }
    
    func getKMACurrent(_ date: Date, _ nx: Int, _ ny: Int, retryCount: Int = 0) {
        Task {
            if let result = await currentWService.fetchW(date: date, nx: nx, ny: ny) {
                DispatchQueue.main.async {
                    self.anyW.currentW = result
                    print("기상청 초단기실황을 불러왔습니다.")
                    
                    self.dispatchGroup.leave()
                }
            } else {
                if retryCount < 3 {
                    print("기상청 초단기실황을 불러오는데에 실패했습니다. 재시도 중...")
                    getKMACurrent(date, nx, ny, retryCount: retryCount + 1)
                } else {
                    print("기상청 초단기실황을 불러오는데 최종적으로 실패했습니다.")
                    self.dispatchGroup.leave()
                }
            }
        }
    }
    
    /// 위치 정보와 도시명을 파라미터로 받아 WeatherKit 데이터를 불러옵니다.
    func getWeatherKit(_ location: CLLocation) {
        Task {
            do {
                let result = try await weatherKitservice.weather(for: location)
                
                /*
                 // 예보 데이터를 배열에 담습니다.
                 result.hourlyForecast.forecast.forEach { hourWeather in
                 self.hourly.append(hourWeather)
                 }
                 result.dailyForecast.forecast.forEach { dayWeather in
                 self.daily.append(dayWeather)
                 }
                 */
                
                self.anyW.apple = result
                print("애플 날씨 정보를 불러왔습니다.")
                self.dispatchGroup.leave()
                
            } catch {
                print("애플 날씨 정보를 불러오는데 실패했습니다.")
                print(String(describing: error))
                self.dispatchGroup.leave()
            }
        }
    }
    
    /// 날씨 데이터를 받아 화면을 업데이트합니다.
    func updateFromAnyWeather(_ w: AnyW, _ address: String) {
        // 날씨 데이터 전달
        homeView.configure(w, address)
        
        // 로티 배경 설정
        let lottieName = w.apple!.currentWeather.condition.conditionToLottieName()
        let lottieName2 = w.apple!.currentWeather.condition.conditionToLottieName2()
        homeView.addBackgroundLottie(lottieName, lottieName2)
        homeView.setUpView()
    }
}

// MARK: - 코어로케이션델리게이트
extension HomeVC: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !hasReceivedLocationUpdate else {
            return
        }
        
        hasReceivedLocationUpdate = true
        self.locationManager.stopUpdatingLocation()
        
        let location: CLLocation = locations[locations.count - 1]
        let longitude: CLLocationDegrees = location.coordinate.longitude
        let latitude: CLLocationDegrees = location.coordinate.latitude
        
        let converter: ConvertXY = ConvertXY()
        let (x, y): (Int, Int)
        = converter.convertGrid(lon: longitude, lat: latitude)
        
        
        let findLocation: CLLocation = CLLocation(latitude: latitude, longitude: longitude)
        let geoCoder: CLGeocoder = CLGeocoder()
        let local: Locale = Locale(identifier: "Ko-kr") // Korea
        geoCoder.reverseGeocodeLocation(findLocation, preferredLocale: local) { (place, error) in
            if let address: [CLPlacemark] = place {
                let locality = address.last?.locality ?? ""
                var regId = ""
                var stnId = ""
                var groupRegId = ""
                
                // 중기기온예보구역코드 반환
                if let regions = loadRegions() {
                    if let reg = regions[String(locality.dropLast(1))] {
                        // 중기육상예보구역코드 반환
                        let groupKey = String(reg.prefix(4))
                        groupRegId = groupKey + "0000"
                        if let group = regionGroups[groupKey + "0000"] {
                            let (regName, stn) = group
                            print("\(locality): \(regName), \(reg), \(stn), \(groupRegId)")
                            regId = reg
                            stnId = stn
                        }
                        else {
                            print("그룹을 찾을 수 없습니다.")
                        }
                    } else {
                        print("구역코드를 찾을 수 없습니다:  \(String(locality.dropLast(1)))")
                    }
                }
                let address = "\(address.last?.locality ?? "") \(address.last?.subLocality ?? "")"
                
                self.getAllWeather(date: Date(), x: x, y: y, loc: location, address: address, regId: regId, stnId: stnId, groupRegId: groupRegId)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("error: \(error)")
    }
}
