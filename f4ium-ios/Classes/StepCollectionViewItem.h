//
//  StepCollectionViewItem.h
//  SonOfGrab
//
//  Created by Mobile_KFTC on 2017. 9. 8..
//
//

#import <Cocoa/Cocoa.h>

@interface StepCollectionViewItem : NSCollectionViewItem

@property (weak) IBOutlet NSTextField *txtTitle;
@property (weak) IBOutlet NSImageView *imgView;
@property (weak) IBOutlet NSButton *radioCoordinate;
@property (weak) IBOutlet NSButton *radioID;
@property (weak) IBOutlet NSTextField *tfCmdCooridatenate;
@property (weak) IBOutlet NSTextField *tfCmdID;
@property (weak) IBOutlet NSTextField *tfComment;
@property (weak) IBOutlet NSButton *btnAddEvent;
@property (weak) IBOutlet NSButton *btnRemoveEvent;

@end
