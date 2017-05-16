//
//  TLPhotoLibrary.swift
//  TLPhotosPicker
//
//  Created by wade.hawk on 2017. 5. 3..
//  Copyright © 2017년 wade.hawk. All rights reserved.
//

import Foundation
import Photos

protocol TLPhotoLibraryDelegate: class {
    func loadCameraRollCollection(collection: TLAssetsCollection)
    func loadCompleteAllCollection(collections: [TLAssetsCollection])
    func focusCollection(collection: TLAssetsCollection)
}

class TLPhotoLibrary {
    
    weak var delegate: TLPhotoLibraryDelegate? = nil
    
    lazy var imageManager: PHCachingImageManager = {
        return PHCachingImageManager()
    }()
    
    deinit {
        //print("deinit TLPhotoLibrary")
    }
    
    @discardableResult
    func livePhotoAsset(asset: PHAsset, size: CGSize = CGSize(width: 720, height: 1280), progressBlock: Photos.PHAssetImageProgressHandler? = nil, completionBlock:@escaping (PHLivePhoto)-> Void ) -> PHImageRequestID {
        let options = PHLivePhotoRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.progressHandler = progressBlock
        let requestId = self.imageManager.requestLivePhoto(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { (livePhoto, info) in
            if let livePhoto = livePhoto {
                completionBlock(livePhoto)
            }
        }
        return requestId
    }
    
    @discardableResult
    func videoAsset(asset: PHAsset, size: CGSize = CGSize(width: 720, height: 1280), progressBlock: Photos.PHAssetImageProgressHandler? = nil, completionBlock:@escaping (AVPlayerItem?, [AnyHashable : Any]?) -> Void ) -> PHImageRequestID {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        options.progressHandler = progressBlock
        let requestId = self.imageManager.requestPlayerItem(forVideo: asset, options: options, resultHandler: { playerItem, info in
            completionBlock(playerItem,info)
        })
        return requestId
    }

    @discardableResult
    func imageAsset(asset: PHAsset, size: CGSize = CGSize(width: 720, height: 1280), options: PHImageRequestOptions? = nil, completionBlock:@escaping (UIImage)-> Void ) -> PHImageRequestID {
        var options = options
        if options == nil {
            options = PHImageRequestOptions()
            options?.deliveryMode = .highQualityFormat
            options?.isNetworkAccessAllowed = false
        }
        let requestId = self.imageManager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { image, info in
            if let image = image {
                completionBlock(image)
            }
        }
        return requestId
    }
    
    func cancelPHImageRequest(requestId: PHImageRequestID) {
        self.imageManager.cancelImageRequest(requestId)
    }
    
    @discardableResult
    func cloudImageDownload(asset: PHAsset, size: CGSize = PHImageManagerMaximumSize, progressBlock: @escaping (Double) -> Void, completionBlock:@escaping (UIImage?)-> Void ) -> PHImageRequestID {
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.version = .current
        options.progressHandler = { (progress,error,stop,info) in
            progressBlock(progress)
        }
        let requestId = self.imageManager.requestImageData(for: asset, options: options) { (imageData, dataUTI, orientation, info) in
            if let data = imageData,let _ = info {
                completionBlock(UIImage(data: data))
            }
        }
        return requestId
    }
    
    @discardableResult
    class func fullResolutionImageData(asset: PHAsset) -> UIImage? {
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.resizeMode = .none
        options.isNetworkAccessAllowed = false
        options.version = .current
        var image: UIImage? = nil
        _ = PHCachingImageManager().requestImageData(for: asset, options: options) { (imageData, dataUTI, orientation, info) in
            if let data = imageData {
                image = UIImage(data: data)
            }
        }
        return image
    }
}

//MARK: - Load Collection
extension TLPhotoLibrary {
    func fetchCollection(allowedVideo: Bool = true, addCameraAsset: Bool = true, mediaType: PHAssetMediaType? = nil) {
        func loadAssets(collection: PHAssetCollection, options: PHFetchOptions?) -> [PHAsset] {
            let assetFetchResult = PHAsset.fetchAssets(in: collection, options: options)
            var assets = [PHAsset]()
            if assetFetchResult.count > 0 {
                assetFetchResult.enumerateObjects({ object, index, stop in
                    assets.insert(object, at: 0)
                })
            }
            return assets
        }
        
        func getUseableCollection(_ fetchCollection: PHFetchResult<PHAssetCollection>) -> PHAssetCollection? {
            let options = PHFetchOptions()
            var result: PHAssetCollection? = nil
            fetchCollection.enumerateObjects({ (collection, index, stop) -> Void in
                if let fetchAssets = PHAsset.fetchKeyAssets(in: collection, options: options), fetchAssets.count > 0 {
                    result = collection
                }
            })
            return result
        }
        
        @discardableResult
        func getSmartAlbum(subType: PHAssetCollectionSubtype, result: inout [TLAssetsCollection]) -> TLAssetsCollection? {
            let fetchCollection = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subType, options: nil)
            if let collection = getUseableCollection(fetchCollection), !result.contains(where: { $0.collection == collection }) {
                let assetsCollection = TLAssetsCollection(collection: collection)
                result.append(assetsCollection)
                return assetsCollection
            }
            return nil
        }
        
        var assetCollections = [TLAssetsCollection]()
        //media type image : default -> Camera Roll
        //media type video : defualt -> Video
        let defaultCollection = getSmartAlbum(subType: mediaType == .video ? .smartAlbumVideos : .smartAlbumUserLibrary, result: &assetCollections)
        let options = PHFetchOptions()
        if let mediaType = mediaType {
            options.predicate = NSPredicate(format: "mediaType = %i", mediaType.rawValue)
        }else if !allowedVideo {
            options.predicate = NSPredicate(format: "mediaType = %i", PHAssetMediaType.image.rawValue)
        }
        if var defaultCollection = defaultCollection {
            DispatchQueue.main.async {
                self.delegate?.focusCollection(collection: defaultCollection)
            }
            defaultCollection.assets = loadAssets(collection: defaultCollection.collection, options: options).map{ TLPHAsset(asset: $0) }
            if addCameraAsset {
                var cameraAsset = TLPHAsset(asset: nil)
                cameraAsset.camera = true
                defaultCollection.assets.insert(cameraAsset, at: 0)
            }
            assetCollections[0] = defaultCollection
            DispatchQueue.main.async {
                self.delegate?.loadCameraRollCollection(collection: defaultCollection)
            }
        }
        DispatchQueue.global(qos: .userInteractive).async { [weak self] _ in
            //Selfies
            getSmartAlbum(subType: .smartAlbumSelfPortraits, result: &assetCollections)
            //Panoramas
            getSmartAlbum(subType: .smartAlbumPanoramas, result: &assetCollections)
            //Favorites
            getSmartAlbum(subType: .smartAlbumFavorites, result: &assetCollections)
            if allowedVideo, mediaType != .video {
                //Videos
                getSmartAlbum(subType: .smartAlbumVideos, result: &assetCollections)
            }
            //Album
            let albumsResult = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
            albumsResult.enumerateObjects({ (collection, index, stop) -> Void in
                if let result = PHAsset.fetchKeyAssets(in: collection, options: options), result.count > 0, !assetCollections.contains(where: { $0.collection == collection }) {
                    assetCollections.append(TLAssetsCollection(collection: collection))
                }
            })
            
            let collections = assetCollections.flatMap{ collection -> TLAssetsCollection? in
                if let defaultCollection = defaultCollection, collection == defaultCollection { return collection }
                var collection = collection
                collection.assets = loadAssets(collection: collection.collection, options: options).map{ TLPHAsset(asset: $0) }
                if collection.assets.count > 0 {
                    return collection
                }
                return nil
            }
            DispatchQueue.main.async {
                self?.delegate?.loadCompleteAllCollection(collections: collections)
            }
        }
    }
}
